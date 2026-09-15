Import-Module DataAgent -RequiredVersion 0.4.0 -ErrorAction Stop
Invoke-DataAgent -SettingsPath "$PSScriptRoot/settings.json"
