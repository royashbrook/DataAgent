Import-Module DataAgent -RequiredVersion 0.10.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
