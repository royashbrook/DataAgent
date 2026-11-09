Import-Module DataAgent -RequiredVersion 0.12.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
