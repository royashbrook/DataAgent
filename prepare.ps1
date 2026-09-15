param([string] $OutputDirectory, [string] $DependencyPath)
$ErrorActionPreference = 'Stop'
if ($DependencyPath) { $env:PSModulePath = $DependencyPath + [IO.Path]::PathSeparator + $env:PSModulePath }
$manifest = Import-PowerShellDataFile "$PSScriptRoot/DataAgent/DataAgent.psd1"
foreach ($dependency in $manifest.RequiredModules) {
    Import-Module -Name $dependency.ModuleName -RequiredVersion $dependency.RequiredVersion -ErrorAction Stop
}
if (!$OutputDirectory) { $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('dataagent-candidate-' + [guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a new staging directory; existing packages are not overwritten.' }
$package = New-Item -ItemType Directory -Path "$OutputDirectory/modules/DataAgent/$($manifest.ModuleVersion)"
foreach ($file in $manifest.FileList) { Copy-Item -LiteralPath "$PSScriptRoot/DataAgent/$file" -Destination $package.FullName }
$dependencies = foreach ($dependency in $manifest.RequiredModules) {
    $module = Get-Module $dependency.ModuleName | Where-Object Version -eq ([version]$dependency.RequiredVersion)
    $target = New-Item -ItemType Directory -Path "$OutputDirectory/modules/$($module.Name)/$($module.Version)"
    Copy-Item -Path "$($module.ModuleBase)/*" -Destination $target.FullName -Recurse
    @{ name = $module.Name; version = $module.Version.ToString() }
}
$consumer = New-Item -ItemType Directory -Path "$OutputDirectory/consumer"
Copy-Item -LiteralPath "$PSScriptRoot/examples/job.ps1", "$PSScriptRoot/examples/settings.json" -Destination $consumer.FullName
Copy-Item -LiteralPath "$PSScriptRoot/try.ps1", "$PSScriptRoot/README.md" -Destination $OutputDirectory
@{
    moduleVersion = $manifest.ModuleVersion; dependencies = @($dependencies)
    files = @(Get-ChildItem "$OutputDirectory/modules" -Recurse -File | ForEach-Object {
        @{ path = [IO.Path]::GetRelativePath($OutputDirectory, $_.FullName); sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant() }
    })
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$OutputDirectory/package.json" -Encoding utf8NoBOM
"Staged candidate: $OutputDirectory"
"Try offline: pwsh -NoProfile -File $OutputDirectory/try.ps1"
