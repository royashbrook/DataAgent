Import-Module DataAgent -RequiredVersion 0.9.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
