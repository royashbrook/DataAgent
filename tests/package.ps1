$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('dataagent-package-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory "$root/repository", "$root/saved"
$name = 'DataAgent-' + [guid]::NewGuid().ToString('N')
try {
    Register-PSRepository -Name $name -SourceLocation "$root/repository" -PublishLocation "$root/repository" -InstallationPolicy Trusted
    Publish-Module -Path "$PSScriptRoot/../DataAgent" -Repository $name
    Save-Module DataAgent -Repository $name -Path "$root/saved"
    $version = (Import-PowerShellDataFile "$PSScriptRoot/../DataAgent/DataAgent.psd1").ModuleVersion
    $installed = "$root/saved/DataAgent/$version"
    & "$PSScriptRoot/capabilities.ps1" -ModulePath $installed
    if ((Get-FileHash "$installed/CAPABILITIES.md").Hash -ne (Get-FileHash "$PSScriptRoot/../DataAgent/CAPABILITIES.md").Hash) { throw 'packaged brief differs' }
    "PASS: published and saved package contains the exact brief ($version)"
} finally {
    if (Get-PSRepository -Name $name -ErrorAction SilentlyContinue) { Unregister-PSRepository -Name $name }
}
