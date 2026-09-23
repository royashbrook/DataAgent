function Invoke-DataAgent {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable] $Config)
    # a module that wraps the runner is the caller, so it names the job's directory instead
    $directory = if ($Config.directory) { $Config.directory } else { $MyInvocation.PSScriptRoot }
    if (!$PSCmdlet.ShouldProcess($directory, 'Invoke-DataAgent')) { return }
    $ErrorActionPreference = 'Stop'
    $ConfirmPreference = 'None'
    Set-Location -LiteralPath $directory
    $log = '{0:yyyyMMdd}.log' -f (Get-Date)
    try {
        & {
            Import-Module Add-PrefixForLogging
            l 'Start'
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
    }
}

Export-ModuleMember -Function Invoke-DataAgent
