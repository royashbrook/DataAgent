Import-Module DataAgent -RequiredVersion 0.11.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
