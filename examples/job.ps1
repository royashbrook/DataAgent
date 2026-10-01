Import-Module DataAgent -RequiredVersion 0.8.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
