Import-Module DataAgent -RequiredVersion 0.4.2 -ErrorAction Stop
$cfg = Get-Content "$PSScriptRoot/settings.json" -Raw | ConvertFrom-Json -AsHashtable
$cfg.src.args.ConnectionString = $env:CONNECTION_STRING
$cfg.dst.args.cfg.msgraph.client_secret = $env:CLIENT_SECRET
Invoke-DataAgent $cfg
