function Get-Adapter($Name, $Role) {
    $path = if ([IO.Path]::GetExtension($Name) -eq '.ps1') { $Name } else { Join-Path $PSScriptRoot "$Role/$Name.ps1" }
    (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
}

function Invoke-DataAgent {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable] $Config, [string] $WorkingDirectory = (Get-Location).Path)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess($WorkingDirectory, 'Invoke-DataAgent')) { return }
    $ConfirmPreference = 'None'
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $src = Get-Adapter $Config.src.adapter 'src'
        $fmt = Get-Adapter $Config.fmt.adapter 'fmt'
        $destinations = foreach ($dst in @($Config.dst)) {
            if ($dst) { @{ path = Get-Adapter $dst.adapter 'dst'; args = $dst.args } }
        }
        Import-Module Add-PrefixForLogging -ErrorAction Stop
        l 'Start'
        if ($Config.purgefiles) {
            Import-Module Clear-Files -ErrorAction Stop
            l 'Cleanup'; Clear-Files $Config
        }
        l 'Get Data'
        $data = @(& $src -Data @() -Options $Config.src.args | Where-Object { $null -ne $_ })
        if (!$data.Count) { l 'No data available'; return }
        l 'Data Found. Formatting File.'
        $options = if ($Config.fmt.args) { @{} + $Config.fmt.args } else { @{} }
        if ($Config.file_format) { $options.Path = $Config.file_format -f (Get-Date) }
        $files = @(& $fmt -Data $data -Options $options)
        if (!$files.Count) { l 'No data available'; return }
        l 'Use Data'
        foreach ($dst in $destinations) { & $dst.path -Data $files -Options $dst.args }
        l 'End'
    } finally { Pop-Location }
}

Export-ModuleMember -Function Invoke-DataAgent
