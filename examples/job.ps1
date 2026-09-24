Import-Module DataAgent -RequiredVersion 0.6.0 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
