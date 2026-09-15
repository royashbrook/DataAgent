$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'
$env:PSModulePath = "$PSScriptRoot/modules" + [IO.Path]::PathSeparator + $env:PSModulePath
$env:DATAAGENT_STATE_ROOT = "$PSScriptRoot/state"
$receipt = & "$PSScriptRoot/consumer/job.ps1" -Mode Mock
Import-Module DataAgent -RequiredVersion 0.3.0
$moduleRoot = (Resolve-Path "$PSScriptRoot/modules").ProviderPath + [IO.Path]::DirectorySeparatorChar
foreach ($name in @('DataAgent', 'Add-PrefixForLogging', 'Clear-Files')) {
    if (!(Get-Module $name).ModuleBase.StartsWith($moduleRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Expected the bundled $name, not a developer-installed copy."
    }
}
if ($receipt.status -ne 'completed' -or !$receipt.deliveries[0].mock) { throw 'Expected a completed mock run.' }
$receipt | Select-Object mode, status, rowCount, workingDirectory, stateDirectory | Format-List
