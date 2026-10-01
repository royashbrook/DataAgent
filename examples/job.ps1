Import-Module DataAgent -RequiredVersion 0.7.2 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
