Import-Module DataAgent -RequiredVersion 0.7.4 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
