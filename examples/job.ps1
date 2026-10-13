Import-Module DataAgent -RequiredVersion 0.7.5 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
