Import-Module DataAgent -RequiredVersion 0.7.3 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
