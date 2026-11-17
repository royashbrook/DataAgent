Import-Module DataAgent -RequiredVersion 0.12.1 -ErrorAction Stop
Invoke-DataAgent "$PSScriptRoot/settings.json"
