Import-Module DataAgent -RequiredVersion 0.7.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
