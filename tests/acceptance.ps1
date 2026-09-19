$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$root = [IO.Directory]::CreateTempSubdirectory('dataagent-acceptance-').FullName
$before = (Get-Location).Path
$priorModules = $env:PSModulePath
$env:PSModulePath = (@($repo, "$repo/testing", "$root/modules", $priorModules) -join [IO.Path]::PathSeparator)
$checks = 0
function Assert($Condition, $Name) { if (!$Condition) { throw "FAIL: $Name" }; $script:checks++ }
function Refuses([scriptblock]$Action, $Pattern) {
    try { & $Action | Out-Null } catch { Assert ("$_" -match $Pattern) "refusal: $Pattern"; return }
    throw "Expected refusal: $Pattern"
}
function Module($Name, $Code) {
    $null = New-Item -ItemType Directory "$root/modules/$Name" -Force
    $Code | Set-Content "$root/modules/$Name/$Name.psm1"
}
function Config($Name) {
    $null = New-Item -ItemType Directory "$root/$Name"
    @{ keepdays = 10; purgefiles = '*.csv,*.log'; src = @{ adapter = 'csv'; args = @{ LiteralPath = "$repo/testing/DataAgent.Test/synthetic.csv" } }; fmt = @{ adapter = 'csv'; args = @{ Path = 'output.csv' } } }
}
function Run($Name, $Config, [switch]$WhatIf) {
    'param($Config,[switch]$WhatIf); Invoke-DataAgent $Config -WhatIf:$WhatIf' | Set-Content "$root/$Name/job.ps1"
    Set-Location $before
    @(& "$root/$Name/job.ps1" $Config -WhatIf:$WhatIf)
}

Import-Module "$repo/DataAgent/DataAgent.psd1" -Force
Assert (@((Get-Module DataAgent).ExportedCommands.Keys) -ceq 'Invoke-DataAgent') 'one public production command'
$core = (Get-FileHash "$repo/DataAgent/DataAgent.psm1").Hash
$cfg = Config 'csv'
$log = Run 'csv' $cfg
$expected = "$root/native.csv"
Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | Export-Csv $expected -NoTypeInformation
Assert ((Get-FileHash "$root/csv/output.csv").Hash -eq (Get-FileHash $expected).Hash) 'native CSV byte parity'
foreach ($phase in @('Start', 'Cleanup', 'Get Data', 'Data Found. Formatting File.', 'Use Data', 'End')) {
    Assert (@($log | Where-Object { $_ -match ("^\d+/\d+/\d+ .*\t\s*\d+\t" + [regex]::Escape($phase) + '$') }).Count -eq 1) "existing l prefix and phase: $phase"
}
'old output' | Set-Content "$root/csv/output.csv"
$null = Run 'csv' $cfg
Assert ((Get-FileHash "$root/csv/output.csv").Hash -eq (Get-FileHash $expected).Hash) 'ordinary overwrite without a toggle'
'expired' | Set-Content "$root/csv/old.csv"
(Get-Item "$root/csv/old.csv").LastWriteTime = (Get-Date).AddDays(-11)
$null = Run 'csv' $cfg
Assert (!(Test-Path "$root/csv/old.csv")) 'existing Clear-Files retention'
Assert ((Get-Location).Path -eq (Join-Path $root 'csv')) 'module stays in calling script directory'
Assert ((Get-Content "$root/csv/$((Get-Date).ToString('yyyyMMdd')).log" -Raw) -match '\tEnd') 'module appends daily job log'
Assert (!(Test-Path "$root/csv/*.receipt.json")) 'no receipt artifacts'

foreach ($mode in @('Always', 'AsNeeded', 'Never', 'Strip')) {
    $c = Config $mode
    $c.fmt.args.UseQuotes = if ($mode -eq 'Strip') { 'Always' } else { $mode }
    $c.fmt.args.StripQuotes = $mode -eq 'Strip'
    $null = Run $mode $c
    $lines = Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | ConvertTo-Csv -UseQuotes $c.fmt.args.UseQuotes
    if ($mode -eq 'Strip') { $lines = $lines | ForEach-Object { $_.Replace('"', '') } }
    $lines | Set-Content $expected -Encoding utf8NoBOM
    Assert ((Get-FileHash "$root/$mode/output.csv").Hash -eq (Get-FileHash $expected).Hash) "$mode native CSV bytes"
}
$cfg = Config 'headerless'; $cfg.fmt.args.NoHeader = $true; $cfg.fmt.args.StripQuotes = $true
$null = Run 'headerless' $cfg
Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | ConvertTo-Csv | Select-Object -Skip 1 | ForEach-Object { $_.Replace('"', '') } | Set-Content $expected
Assert ((Get-FileHash "$root/headerless/output.csv").Hash -eq (Get-FileHash $expected).Hash) 'headerless legacy quote stripping'
$cfg = Config 'dated'; $cfg.file_format = '{0:yyyyMMdd}-feed.csv'
$null = Run 'dated' $cfg
Assert (Test-Path "$root/dated/$((Get-Date).ToString('yyyyMMdd'))-feed.csv") 'legacy file_format naming'

$cfg = Config 'empty'; 'id,name' | Set-Content "$root/empty-input.csv"
$cfg.src.args.LiteralPath = "$root/empty-input.csv"
'param($Data,$Options); throw "destination must not run"' | Set-Content "$root/empty/send.ps1"
$cfg.dst = @{ adapter = './send.ps1'; args = @{} }
$log = Run 'empty' $cfg
Assert (!(Test-Path "$root/empty/output.csv") -and @($log | Where-Object { $_ -match 'No data available$' }).Count -eq 1) 'empty source logs and sends nothing'
$cfg = Config 'preview'; $cfg.src.adapter = 'not-installed'
'keep' | Set-Content "$root/preview/old.csv"
(Get-Item "$root/preview/old.csv").LastWriteTime = (Get-Date).AddDays(-20)
$null = Run 'preview' $cfg -WhatIf
Assert (Test-Path "$root/preview/old.csv") 'top-level WhatIf skips imports and cleanup'
Assert ((Get-Location).Path -eq $before -and !(Test-Path "$root/preview/*.log")) 'WhatIf leaves directory and logs alone'

$cfg = Config 'bad-adapter'; $cfg.src.adapter = 'missing'
'expired' | Set-Content "$root/bad-adapter/old.csv"
(Get-Item "$root/bad-adapter/old.csv").LastWriteTime = (Get-Date).AddDays(-11)
Refuses { Run 'bad-adapter' $cfg } 'missing'
Assert (!(Test-Path "$root/bad-adapter/old.csv")) 'cleanup precedes adapter loading'

Module SqlServer @'
$script:seen = $null
function Invoke-Sqlcmd {
    param($ConnectionString, $InputFile, $QueryTimeout, $OutputAs, $Query)
    $script:seen = $PSBoundParameters
    if ($Query -eq 'fail') { throw 'source failed' }
    if ($ConnectionString -ne 'synthetic connection') { throw 'connection not forwarded' }
    if ($Query -match '^tables:([0-9,]+)$') {
        $ds = [Data.DataSet]::new()
        foreach ($count in $Matches[1].Split(',')) {
            $table = [Data.DataTable]::new()
            $null = $table.Columns.Add('id', [int]); $null = $table.Columns.Add('text', [string])
            for ($i = 1; $i -le [int]$count; $i++) { $null = $table.Rows.Add($i, 'kept') }
            $null = $ds.Tables.Add($table)
        }
        $ds.Tables
        return
    }
    Import-Csv -LiteralPath $InputFile
}
'@
$cfg = Config 'sql'
Copy-Item "$repo/testing/DataAgent.Test/synthetic.csv" "$root/sql/rows.csv"
$cfg.src = @{ adapter = 'sql'; args = @{ ConnectionString = 'synthetic connection'; InputFile = 'rows.csv'; QueryTimeout = 37; OutputAs = 'DataTables' } }
$cfg.purgefiles = '*.log'
$null = Run 'sql' $cfg
$seen = & (Get-Module -All SqlServer) { $script:seen }
Assert ($seen.ConnectionString -eq 'synthetic connection' -and $seen.InputFile -eq 'rows.csv' -and $seen.QueryTimeout -eq 37) 'SQL arguments and relative caller path pass through'
foreach ($counts in '0', '1', '3', '0,0', '0,2,0,1') {
    $name = "sql-tables-$counts"
    $c = Config $name
    $c.src = @{ adapter = 'sql'; args = @{ ConnectionString = 'synthetic connection'; Query = "tables:$counts"; OutputAs = 'DataTables' } }
    $rows = @(foreach ($count in $counts.Split(',')) { for ($i = 1; $i -le [int]$count; $i++) { [pscustomobject]@{ id = $i; text = 'kept' } } })
    if (!$rows.Count) {
        'param($Data,$Options); throw "empty SQL must not deliver"' | Set-Content "$root/$name/send.ps1"
        $c.dst = @{ adapter = './send.ps1'; args = @{} }
    }
    $messages = Run $name $c
    if (!$rows.Count) {
        Assert (!(Test-Path "$root/$name/output.csv")) "empty SQL tables $counts create no artifact"
        Assert (@($messages | Where-Object { $_ -match 'No data available$' }).Count -eq 1) "empty SQL tables $counts use idle path"
    } else {
        $rows | Export-Csv $expected -NoTypeInformation
        Assert ((Get-FileHash "$root/$name/output.csv").Hash -eq (Get-FileHash $expected).Hash) "SQL tables $counts preserve row bytes and order"
    }
}
$cfg.src.args.Query = 'fail'
Refuses { Run 'sql' $cfg } 'source failed'
Assert ((Get-Location).Path -eq (Join-Path $root 'sql')) 'job directory remains after failure'
$null = New-Item -ItemType Directory "$root/tee-failure"
Copy-Item "$repo/examples/job.ps1" "$root/tee-failure/job.ps1"
@{ src = @{ adapter='sql'; args=@{Query='fail'} }; fmt=@{adapter='csv';args=@{Path='output.csv'}};dst=@{adapter='email';args=@{cfg=@{msgraph=@{}}}} } |
    ConvertTo-Json -Depth 8 | Set-Content "$root/tee-failure/settings.json"
$PSNativeCommandUseErrorActionPreference = $false
$console = & (Get-Process -Id $PID).Path -NoProfile -File "$root/tee-failure/job.ps1" 2>&1
Assert ($LASTEXITCODE -eq 1) 'example job reports terminating failure to scheduler'
$errorLog = Get-Content (Join-Path "$root/tee-failure" ('{0:yyyyMMdd}.log' -f (Get-Date))) -Raw
Assert ($errorLog -match 'source failed') 'example tee records terminating error as well as phases'
$global:LASTEXITCODE = 0

# Unchanged converter, selected DataTable rows, no adapter-specific public API.
$cfg = Config 'custom'
@'
param($Data,$Options)
$dt = [Data.DataTable]::new()
$null = $dt.Columns.Add('id',[int]); $null = $dt.Columns.Add('text',[string])
$null = $dt.Rows.Add(12,'keep'); $null = $dt.Rows.Add(99,'excluded')
$dt.Rows[0]
'@ | Set-Content "$root/custom/src.ps1"
@'
function ConvertTo-Custom([Data.DataTable]$dt) { foreach($row in $dt.Rows) { '{0}|{1}' -f $row.id,$row.text } }
Export-ModuleMember -Function ConvertTo-Custom
'@ | Set-Content "$root/custom/ConvertTo-Custom.psm1"
$hash = (Get-FileHash "$root/custom/ConvertTo-Custom.psm1").Hash
$cfg.src = @{ adapter = './src.ps1'; args = @{} }
$cfg.fmt = @{ adapter = 'custom'; args = @{ Module = './ConvertTo-Custom.psm1'; Path = 'output.txt' } }
$null = Run 'custom' $cfg
Assert ((Get-Content "$root/custom/output.txt" -Raw).Trim() -eq '12|keep') 'custom receives selected rows as DataTable'
Assert ((Get-FileHash "$root/custom/ConvertTo-Custom.psm1").Hash -eq $hash) 'converter untouched'
$cfg = Config 'xlsx'
$cfg.fmt = @{ adapter = 'xlsx'; args = @{ Path = 'output.xlsx'; WorksheetName = 'Rows'; NoNumberConversion = @('*'); TableStyle = 'Medium6' } }
$null = Run 'xlsx' $cfg
Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | Export-Excel "$root/native.xlsx" -WorksheetName Rows -NoNumberConversion '*' -TableStyle Medium6
$actual = Import-Excel "$root/xlsx/output.xlsx" | ConvertTo-Json -Compress
$native = Import-Excel "$root/native.xlsx" | ConvertTo-Json -Compress
Assert ($actual -eq $native) 'XLSX native cell semantics including newline normalization'

# The real email helper runs; only its HTTP boundary is replaced in this process.
Import-Module Send-FileViaEmail -RequiredVersion 2.0.0.0
& (Get-Module Send-FileViaEmail) {
    $script:messages = [Collections.Generic.List[object]]::new()
    function script:Invoke-RestMethod {
        param($URI,$Method,$Body,$Headers,$ContentType)
        if ($URI -like 'https://login.microsoftonline.com/*') {
            if ($Body.client_secret -ne 'synthetic secret') { throw 'secret not forwarded' }
            return @{ access_token = 'synthetic token' }
        }
        if ($URI -notlike 'https://graph.microsoft.com/v1.0/users/*/sendMail') { throw 'unexpected endpoint' }
        $script:messages.Add(($Body | ConvertFrom-Json -AsHashtable))
    }
}
$cfg = Config 'email'
$cfg.dst = @{ adapter = 'email'; args = @{ cfg = @{ msgraph = @{ tenant_id = 'example'; client_id = 'example'; client_secret = 'synthetic secret' }; mail = @{ from = 'from@example.invalid'; to = @('to@example.invalid'); subject = 'literal {subject}' } } } }
$log = Run 'email' $cfg
$messages = @(& (Get-Module Send-FileViaEmail) { $script:messages.ToArray() })
Assert ($messages.Count -eq 1 -and $messages[0].message.subject -eq 'literal {subject}') 'existing email helper gets caller config'
Assert ($messages[0].message.attachments[0].contentBytes -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes("$root/email/output.csv"))) 'existing helper attachment bytes'
Assert ($messages[0].message.attachments[0].name -eq 'output.csv') 'existing helper attachment name stays a basename'
Assert (($log -join "`n") -notmatch 'synthetic secret|synthetic connection') 'runner does not echo config'
Refuses { & "$repo/DataAgent/dst/email.ps1" -Data @('one.csv','two.csv') -Options $cfg.dst.args } 'one file'
Assert (@(& (Get-Module Send-FileViaEmail) { $script:messages.ToArray() }).Count -eq 1) 'multiple files refused before any email'
Assert ((Get-Location).Path -eq (Join-Path $root 'email')) 'email does not change directory'

$cfg = Config 'extension'
@'
param($Data,$Options)
foreach($name in $Options.Path) { 'example' | Set-Content $name }
'@ | Set-Content "$root/extension/fmt.ps1"
'param([string[]]$Data,$Options); $Data -join "," | Add-Content $Options.Path' | Set-Content "$root/extension/dst.ps1"
$cfg.fmt = @{ adapter = './fmt.ps1'; args = @{ Path = @('first.txt','second.txt') } }
$cfg.dst = @(@{ adapter = './dst.ps1'; args = @{ Path = 'one.txt' } }, @{ adapter = './dst.ps1'; args = @{ Path = 'two.txt' } })
$null = Run 'extension' $cfg
Assert ((Get-Content "$root/extension/one.txt") -eq 'first.txt,second.txt' -and (Get-Content "$root/extension/two.txt") -eq 'first.txt,second.txt') 'external formatter and destinations without core edit'
Assert ((Get-FileHash "$repo/DataAgent/DataAgent.psm1").Hash -eq $core) 'core unchanged by extensions'
$logPath = Join-Path "$root/extension" ('{0:yyyyMMdd}.log' -f (Get-Date))
$null = Run 'extension' $cfg
Assert (@(Get-Content $logPath | Where-Object { $_ -match '\tEnd$' }).Count -eq 2) 'built-in daily tee appends across runs'

. "$PSScriptRoot/transfers.ps1"

foreach ($package in @('DataAgent','testing/DataAgent.Test')) {
    $name = Split-Path $package -Leaf
    $manifest = Test-ModuleManifest "$repo/$package/$name.psd1"
    foreach ($file in $manifest.FileList) { Assert (Test-Path $file) "package includes $file" }
    $target = New-Item -ItemType Directory "$root/staged/$name" -Force
    Copy-Item "$repo/$package/*" $target.FullName -Recurse
}
Remove-Module DataAgent -Force
$env:PSModulePath = (@("$root/staged", $priorModules) -join [IO.Path]::PathSeparator)
Import-Module DataAgent.Test -RequiredVersion 0.4.2
$result = @(Test-DataAgent)
Assert (@($result | Where-Object { $_ -is [IO.FileInfo] -and $_.Name -eq 'output.csv' }).Count -eq 1) 'staged optional test package exercises bundled formatter'
$env:PSModulePath = $priorModules
Set-Location $before
"PASS: $checks checks; evidence: $root"
