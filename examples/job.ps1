param([ValidateSet('Mock', 'ExportOnly', 'Live')][string] $Mode = 'Mock')
Import-Module DataAgent -RequiredVersion 0.3.0 -ErrorAction Stop
Invoke-DataAgent -SettingsPath "$PSScriptRoot/settings.json" -Mode $Mode
