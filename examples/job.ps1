Import-Module DataAgent -RequiredVersion 0.7.1 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
