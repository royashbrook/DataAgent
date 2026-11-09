# sent: rows a receipt already names are skipped, and a receipt is written only after every destination
# returned. a stub destination counts what it was handed and fails when told to.
$dst = 'param($Data,$Options); if (Test-Path fail.flag) { throw "send refused" }; (Import-Csv $Data).Count | Add-Content sends.txt'
function Sends($Name) { @(Get-Content "$root/$Name/sends.txt" -ErrorAction Ignore) }
function Receipts($Name) { @(Get-ChildItem "$root/$Name/sent" -Filter *.txt -ErrorAction Ignore) }

$cfg = Config 'sent-key'
$dst | Set-Content "$root/sent-key/dst.ps1"
$cfg.dst = @{ adapter = './dst.ps1'; args = @{} }
$cfg.sent = @{ key = 'Id'; keep_days = 14 }
$null = Run 'sent-key' $cfg
Assert ((Sends 'sent-key') -join ',' -eq '5' -and (Receipts 'sent-key').Count -eq 1) 'first run sends every row and writes one receipt'
Assert ((Get-Content (Receipts 'sent-key')[0].FullName) -join ',' -eq '1,2,3,4,5') 'the receipt names each key once'
$log = Run 'sent-key' $cfg
Assert ((Sends 'sent-key').Count -eq 1 -and ($log -match 'No data available')) 'a second run sends nothing'

# one new row goes, the rest stay skipped
Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | Select-Object -First 2 | Export-Csv "$root/sent-key/more.csv"
[pscustomobject]@{ Id = '6'; Description = 'new'; Quantity = '1' } | Export-Csv "$root/sent-key/more.csv" -Append
$cfg.src.args.LiteralPath = "$root/sent-key/more.csv"
Start-Sleep 1
$null = Run 'sent-key' $cfg
Assert ((Sends 'sent-key')[-1] -eq '1' -and (Receipts 'sent-key').Count -eq 2) 'only the new row goes'

# a receipt past keep_days is removed by its name's date, and its rows go again
Rename-Item (Receipts 'sent-key')[0].FullName ('20000101000000.txt')
$cfg.src.args.LiteralPath = "$repo/testing/DataAgent.Test/synthetic.csv"
Start-Sleep 1
$null = Run 'sent-key' $cfg
Assert ((Sends 'sent-key')[-1] -eq '5' -and !(Test-Path "$root/sent-key/sent/20000101000000.txt")) 'an expired receipt is dropped and its rows go again'

# a failed destination marks nothing sent
$cfg = Config 'sent-fail'
$dst | Set-Content "$root/sent-fail/dst.ps1"
'' | Set-Content "$root/sent-fail/fail.flag"
$cfg.dst = @{ adapter = './dst.ps1'; args = @{} }
$cfg.sent = @{ key = 'Id'; path = 'receipts' }
Refuses { Run 'sent-fail' $cfg } 'send refused'
Assert (!(Test-Path "$root/sent-fail/receipts")) 'a failed send writes no receipt'
Remove-Item "$root/sent-fail/fail.flag"
$null = Run 'sent-fail' $cfg
Assert ((Sends 'sent-fail') -join ',' -eq '5' -and @(Get-ChildItem "$root/sent-fail/receipts").Count -eq 1) 'the next run sends them, receipts in the named path'

# format-only filters but marks nothing
$cfg = Config 'sent-format'
$cfg.sent = @{ key = 'Id' }
$null = Run 'sent-format' $cfg
Assert ((Test-Path "$root/sent-format/output.csv") -and !(Test-Path "$root/sent-format/sent")) 'a format-only run writes no receipt'

# whole row: an edited row is a new row. a value with a line break and quotes compares the same.
$cfg = Config 'sent-row'
$dst | Set-Content "$root/sent-row/dst.ps1"
$cfg.dst = @{ adapter = './dst.ps1'; args = @{} }
$cfg.sent = @{}
$cfg.sent.path = 'sent'
$null = Run 'sent-row' $cfg
$null = Run 'sent-row' $cfg
Assert ((Sends 'sent-row') -join ',' -eq '5') 'whole rows, the multi-line and quoted ones too, are skipped on the rerun'
$rows = Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv"
$rows[0].Quantity = '13'
$rows | Export-Csv "$root/sent-row/edited.csv"
$cfg.src.args.LiteralPath = "$root/sent-row/edited.csv"
Start-Sleep 1
$null = Run 'sent-row' $cfg
Assert ((Sends 'sent-row')[-1] -eq '1') 'an edited row goes again'

# a list of fields is one key
$cfg = Config 'sent-pair'
$dst | Set-Content "$root/sent-pair/dst.ps1"
$cfg.dst = @{ adapter = './dst.ps1'; args = @{} }
$cfg.sent = @{ key = @('Id', 'Quantity') }
$null = Run 'sent-pair' $cfg
$rows = Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv"
$rows[0].Description = 'renamed'; $rows[1].Quantity = '7'
$rows | Export-Csv "$root/sent-pair/changed.csv"
$cfg.src.args.LiteralPath = "$root/sent-pair/changed.csv"
Start-Sleep 1
$null = Run 'sent-pair' $cfg
Assert ((Sends 'sent-pair')[-1] -eq '1') 'only a change to a key field makes a row new'

# a run in the same second as an earlier receipt keeps that receipt's keys
$cfg = Config 'sent-second'
$dst | Set-Content "$root/sent-second/dst.ps1"
$cfg.dst = @{ adapter = './dst.ps1'; args = @{} }
$cfg.sent = @{ key = 'Id' }
$null = New-Item -ItemType Directory "$root/sent-second/sent"
$now = Get-Date
foreach ($s in 0..30) { 'earlier' | Set-Content ("$root/sent-second/sent/{0:yyyyMMddHHmmss}.txt" -f $now.AddSeconds($s)) }
$null = Run 'sent-second' $cfg
Assert (@(Get-ChildItem "$root/sent-second/sent" | Where-Object { @(Get-Content $_.FullName)[0] -ne 'earlier' }).Count -eq 0) 'a same-second receipt is appended to, not replaced'

# keys that differ only by case, or by unicode form (e-acute vs e + combining acute), are different
# keys, all recorded and all skipped after
$cfg = Config 'sent-case'
$dst | Set-Content "$root/sent-case/dst.ps1"
@(
    [pscustomobject]@{ Id = 'abc'; Description = 'lower' }
    [pscustomobject]@{ Id = 'ABC'; Description = 'upper' }
    [pscustomobject]@{ Id = "caf$([char]0x00E9)"; Description = 'composed' }
    [pscustomobject]@{ Id = "cafe$([char]0x0301)"; Description = 'decomposed' }
) | Export-Csv "$root/sent-case/case.csv"
$cfg.src.args.LiteralPath = "$root/sent-case/case.csv"
$cfg.dst = @{ adapter = './dst.ps1'; args = @{} }
$cfg.sent = @{ key = 'Id' }
$null = Run 'sent-case' $cfg
$null = Run 'sent-case' $cfg
Assert ((Sends 'sent-case') -join ',' -eq '4' -and @(Get-Content (Receipts 'sent-case')[0].FullName).Count -eq 4) 'case and unicode-form distinct keys all recorded, nothing sent twice'

# a key that is not a column would skip everything after one send, so it stops the run
$cfg = Config 'sent-missing'
$cfg.sent = @{ key = 'InvoiceNumber' }
Refuses { Run 'sent-missing' $cfg } "sent.key 'InvoiceNumber' is not a column"
