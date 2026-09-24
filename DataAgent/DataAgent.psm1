function Resolve-Setting {
    param($Value)
    # 'env:NAME' is read when the run starts, so a secret lives in the environment and the config
    # only names it
    if ($Value -is [string] -and $Value -match '^env:(.+)$') {
        $found = [Environment]::GetEnvironmentVariable($Matches[1])
        if ([string]::IsNullOrEmpty($found)) { throw "environment variable $($Matches[1]) is not set." }
        return $found
    }
    if ($Value -is [Collections.IDictionary]) {
        $resolved = @{}
        foreach ($key in $Value.Keys) { $resolved[$key] = Resolve-Setting $Value[$key] }
        # a username and a password, and nothing else, is a login
        if ($resolved.Count -eq 2 -and $resolved.ContainsKey('username') -and $resolved.ContainsKey('password')) {
            return [pscredential]::new($resolved.username, [Net.NetworkCredential]::new('', $resolved.password).SecurePassword)
        }
        return $resolved
    }
    # arrays from JSON and lists from a script caller alike
    if ($Value -is [Collections.IList]) { return , @($Value | ForEach-Object { Resolve-Setting $_ }) }
    $Value
}

function Invoke-DataAgent {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Config)
    # a path is a settings file, and the run works in its folder unless the settings name one; a
    # relative directory in the file means relative to the file, not to wherever the caller stands
    if ($Config -is [string]) {
        $file = Get-Item -LiteralPath $Config
        $Config = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        $Config.directory = if (!$Config.directory) { $file.DirectoryName }
            else { [IO.Path]::GetFullPath($Config.directory, $file.DirectoryName) }
    }
    # a module that wraps the runner is the caller, so it names the job's directory instead
    $directory = if ($Config.directory) { $Config.directory } else { $MyInvocation.PSScriptRoot }
    if (!$PSCmdlet.ShouldProcess($directory, 'Invoke-DataAgent')) { return }
    $ErrorActionPreference = 'Stop'
    $ConfirmPreference = 'None'
    Set-Location -LiteralPath $directory
    $log = '{0:yyyyMMdd}.log' -f (Get-Date)
    # colour codes stay on the screen and out of the log
    $rendering = $PSStyle.OutputRendering
    $PSStyle.OutputRendering = 'Host'
    try {
        & {
            Import-Module Add-PrefixForLogging
            l 'Start'
            $Config = Resolve-Setting $Config
            if ($Config.purgefiles) {
                Import-Module Clear-Files
                l 'Cleanup'; Clear-Files $Config
            }
            $adapters = @{}
            foreach ($role in 'src', 'fmt', 'dst') {
                $adapters[$role] = @(foreach ($entry in @($Config[$role])) {
                    if ($entry) { if ($entry.adapter -like '*.ps1') { $entry.adapter } else { "$PSScriptRoot/$role/$($entry.adapter).ps1" } }
                })
            }
            l 'Get Data'
            $data = @(& ($adapters.src[0]) -Data @() -Options $Config.src.args | Where-Object { $null -ne $_ })
            if (!$data.Count) { l 'No data available'; return }
            l 'Data Found. Formatting File.'
            $options = if ($Config.fmt.args) { @{} + $Config.fmt.args } else { @{} }
            if ($Config.file_format) { $options.Path = $Config.file_format -f (Get-Date) }
            $file = $options.Path
            & ($adapters.fmt[0]) -Data $data -Options $options
            l 'Use Data'
            for ($i = 0; $i -lt $adapters.dst.Count; $i++) { & ($adapters.dst[$i]) -Data $file -Options @($Config.dst)[$i].args }
            l 'End'
        } *>&1 | Tee-Object -Append $log
    } catch {
        $_ | Out-String | Add-Content -LiteralPath $log
        throw
    } finally {
        $PSStyle.OutputRendering = $rendering
    }
}

Export-ModuleMember -Function Invoke-DataAgent
