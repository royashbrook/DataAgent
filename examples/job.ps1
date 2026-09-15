Import-Module DataAgent -RequiredVersion 0.4.0 -ErrorAction Stop
$cfg = Get-Content "$PSScriptRoot/settings.json" -Raw | ConvertFrom-Json -AsHashtable
$cfg.src.args.ConnectionString = $env:CONNECTION_STRING
$cfg.dst.args.cfg.msgraph.client_secret = $env:CLIENT_SECRET
$failed = $false
& { try { Invoke-DataAgent $cfg -WorkingDirectory $PSScriptRoot } catch { $script:failed = $true; $_ } } *>&1 |
    Tee-Object -Append (Join-Path $PSScriptRoot ('{0:yyyyMMdd}.log' -f (Get-Date)))
if ($failed) { exit 1 }
