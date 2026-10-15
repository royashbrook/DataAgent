param([string] $ModulePath = "$PSScriptRoot/../DataAgent")
$ErrorActionPreference = 'Stop'
$ModulePath = (Resolve-Path $ModulePath).Path
$root = [IO.Directory]::CreateTempSubdirectory('dataagent-invoice-').FullName
$before = Get-Location
$checks = 0
function Check($Condition, $Name) { if (!$Condition) { throw "FAIL: $Name" }; $script:checks++ }
function Format($Name, $Rows, $Options) {
    $Options.Path = "$root/$Name.txt"
    & "$ModulePath/fmt/$Name.ps1" -Data $Rows -Options $Options
    @(Get-Content -LiteralPath $Options.Path)
}

. "$ModulePath/fmt/invoice/template.ps1"
Check ((Expand-InvoiceLine '{id,-5}|{amount:0.00}|{invoice.id}|{absent}' @{id='row';amount=1.5} @{id='SYN';invoice=@{id='A'}}) -ceq 'SYN  |1.50|A|') 'padding, precision, dotted lookup, missing field and config precedence'
Check ((Expand-InvoiceLine '{id,2}|$(never-run)' @{id='LONG'}) -ceq 'LONG|$(never-run)') 'width does not truncate and templates do not execute code'

$culture = [Globalization.CultureInfo]::CurrentCulture
try {
    foreach ($name in 'en-US', 'fr-FR') {
        [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($name)
        foreach ($value in @([datetime]'2026-10-14T13:05:00', [decimal]'1234.50')) {
            Check ((Expand-InvoiceLine '{value}' @{value=$value}) -ceq "$value") "$name plain $($value.GetType().Name) keeps interpolation bytes"
            Check ((Expand-InvoiceLine '{value,-32}' @{value=$value}) -ceq ('{0,-32}' -f "$value")) "$name alignment pads the interpolated value"
            $format = if ($value -is [datetime]) { 'yyyyMMdd HH:mm' } else { 'N2' }
            Check ((Expand-InvoiceLine ('{value:' + $format + '}') @{value=$value}) -ceq (('{0:' + $format + '}') -f $value)) "$name explicit format still receives the typed value"
        }
    }
} finally { [Globalization.CultureInfo]::CurrentCulture = $culture }

$table = [Data.DataTable]::new()
foreach ($name in 'ivh_invoicenumber','ivh_billdate','ivh_totalcharge','dori','ivd_refnum','ivh_consignee','cmd_code','not_text','ivd_quantity','ivd_wgt','ivd_rate','ivd_charge','cht_itemcode') { $null = $table.Columns.Add($name) }
$null = $table.Rows.Add(@('B','20261014','2','d','B1','C','DSL','note, one','1','2','2','2','FRT'))
$null = $table.Rows.Add(@('A','20261014','3','i','','C','','','1','0','1','1','FSC'))
$null = $table.Rows.Add(@('A','20261014','3','d','A1','C','DSL','','1','2','2','2','FRT'))
$lines = Format pdi @($table.Rows) @{Values=@{sender_id='SYN'}}
$expected = @(
    '"H","SYN","A","20261014",,,,,,"3","N"'
    '"D","A1","C","DSL","","SYN",,"1","2","2",,"2",'
    '"I","FSC","1",'
    '"H","SYN","B","20261014",,,,,,"2","N"'
    '"D","B1","C","DSL","note, one","SYN",,"1","2","2",,"2",'
)
$expected | Set-Content "$root/expected.txt" -Encoding utf8NoBOM
Check ((Get-FileHash "$root/pdi.txt").Hash -ceq (Get-FileHash "$root/expected.txt").Hash) 'pdi DataRow input has exact H/D/I bytes, sorted invoices and D before I'
$lines = Format pdi @([pscustomobject]@{id='A';kind='d';amount=2}) @{Key='id';Head='id';Type='kind';H='H,{id}';D='D,{amount:0.00}';I=''}
Check (($lines -join '|') -ceq 'H,A|D,2.00') 'pdi record selectors and whole templates can be replaced'

$dated = $table.Clone()
$dated.Columns['ivh_billdate'].DataType = [datetime]
$date = [datetime]'2026-10-14T13:05:00'
$null = $dated.Rows.Add(@('A',$date,'3','d','A1','C','DSL','','1','2','2','2','FRT'))
$lines = Format pdi @($dated.Rows) @{Values=@{sender_id='SYN'}}
Check ($lines[0] -ceq ('"H","SYN","A","{0}",,,,,,"3","N"' -f "$date")) 'pdi DateTime DataRow preserves the legacy interpolated date'
$lines = Format pdi @($dated.Rows) @{H='"H","{ivh_billdate:yyyyMMdd}"'}
Check ($lines[0] -ceq '"H","20261014"') 'pdi DateTime DataRow still supports explicit formatting'

$rows = @(
    [pscustomobject]@{ b302='A';b303='B1';b306='20261014';b307='3.00';b309='20261014';b312='PP';l502='DSL';l507='DIESEL';l004=2;l006=2;l102=1;l104=2 }
    [pscustomobject]@{ b302='A';b303='B1';b306='20261014';b307='3.00';b309='20261014';b312='PP';l502='FSC';l507='FUEL';l004=1;l006=1;l102=1;l104=1 }
    [pscustomobject]@{ b302='B';b303='B2';b306='20261014';b307='1.00';b309='20261014';b312='PP';l502='DSL';l507='DIESEL';l004=1;l006=1;l102=1;l104=1 }
)
$values = @{sender_id='SYN';receiver_id='RECEIVER';company_name='Synthetic Carrier';company_address='1 Example St';company_city='Example';company_state='FL';company_zip='00000';now=[datetime]'2026-10-14T09:30:00';control=260123}
$lines = Format x12-210 $rows @{Values=$values}
$isa = 'ISA*00*          *00*          *02*SYN            *ZZ*RECEIVER       *261014*0930*U*00401*000260123*0*P*>'
Check ($lines[0] -ceq $isa) 'every default ISA field, including padding, date, time, control and component separator'
Check ($lines[1] -ceq 'GS*IM*SYN*RECEIVER*20261014*0930*260123*X*004010') 'every GS field uses the same filing time and configured identifiers'
Check ($lines[-2] -ceq 'GE*2*260123' -and $lines[-1] -ceq 'IEA*1*000260123') 'GE/IEA counts and control numbers match their envelopes'
Check (@($lines | Where-Object { $_ -ceq 'SE*22*000000001' }).Count -eq 1 -and @($lines | Where-Object { $_ -ceq 'SE*18*000000002' }).Count -eq 1) 'actual ST-through-SE segment counts for multiple invoices and details'
Check (@($lines | Where-Object { $_ -ceq 'LX*001' }).Count -eq 2 -and @($lines | Where-Object { $_ -ceq 'LX*002' }).Count -eq 1) 'line numbering restarts in each invoice'
$variant = @{} + $values
$lines = Format x12-210 $rows @{Values=$variant;Head=@('ISA*{sender_id,-10}*000{control}','GS*000{control}');Tail=@('GE*{invoices}*{control}','IEA*1*{control}');SeExtra=2}
Check ($lines[0] -ceq 'ISA*SYN       *000260123' -and $lines[1] -ceq 'GS*000260123' -and $lines[-1] -ceq 'IEA*1*260123') 'legacy width and inconsistent prefix stay explicit template overrides'
Check (@($lines | Where-Object { $_ -ceq 'SE*24*000000001' }).Count -eq 1) 'a legacy count offset is explicit, not the default'

$invoices = @(
    @{ivh_invoicenumber='A';ivh_billdate='20261014';ivh_totalcharge=3;ShipDate='20261013';ShipTime='0830';Detail=@(@{RecordType='ITMF';bol='B1';ivd_description='DIESEL';cmd_code='DSL';ivd_quantity=2;ivd_wgt=3;ivd_unit='GA';ivd_rate=1;ivd_charge=2},@{RecordType='OTHF';ivd_rate=1;ivd_charge=1})}
    @{ivh_invoicenumber='B';Detail=@(@{RecordType='ITMF';ivd_rate=1.23456;ivd_charge=2.345})}
)
$values = @{sender_id='SYNDTN';terms='NET-30';dtn=@{user='synthetic-user';pass='synthetic-password';site='SYN-SITE'}}
$lines = Format dtn $invoices @{Values=$values}
Check ($lines[0] -ceq 'synthetic-user,synthetic-password' -and $lines[1] -ceq 'INF' -and $lines[3] -ceq 'SYN-SITE') 'DTN login and site are configured values'
Check ($lines[2] -ceq 'C02,1001,  /  /  ,00:00,COMP,2,0001,S' -and $lines[9] -ceq 'C02,1002,  /  /  ,00:00,COMP,2,0001,S') 'one numbered DTN block per nested invoice'
Check ($lines[5].Split(',').Count -eq 35 -and $lines[5] -like '"INVH","SYNDTN","A",*"NET-30"*') 'DTN header order, field count, sender and terms'
Check ($lines[6] -ceq '"ITMF","B1","DIESEL","DSL","G","2","3","2","GA","1.0000","2.00","20261013","0830","","",""') 'DTN detail has exact precision, parent date/time and trailing empty columns'
Check ($lines[13] -ceq '"ITMF","","","","G","","","","","1.2346","2.35","","","","",""') 'DTN next invoice does not inherit parent data'
Check ($lines[-1] -ceq '<!--END OF FILE-->') 'DTN file trailer'
$profile = Import-PowerShellDataFile "$ModulePath/fmt/invoice/dtn.psd1"
$profile.Line[9] = '{ivd_rate:N4}'; $profile.Line[10] = '{ivd_charge:N4}'
$profile.Values = $values
$lines = Format dtn $invoices $profile
Check ($lines[6] -like '*"1.0000","2.0000"*') 'DTN receiver precision variant is a template override'

try {
    Import-Module "$ModulePath/DataAgent.psd1" -Force
    $job = New-Item -ItemType Directory "$root/runner"
    $invoices | ConvertTo-Json -Depth 8 | Set-Content "$job/rows.json"
    'param($Data,$Options); Get-Content $Options.InputFile -Raw | ConvertFrom-Json' | Set-Content "$job/source.ps1"
    $env:DATAAGENT_INVOICE_TEST_USER='synthetic-user'
    $config = @{directory=$job.FullName;src=@{adapter='./source.ps1';args=@{InputFile='rows.json'}};fmt=@{adapter='dtn';args=@{Path='out.txt';Values=@{sender_id='SYNDTN';terms='NET-30';dtn=@{user='env:DATAAGENT_INVOICE_TEST_USER';pass='synthetic-password';site='SYN-SITE'}}}}}
    $null = Invoke-DataAgent $config
    Check ((Get-Content "$job/out.txt")[0] -ceq 'synthetic-user,synthetic-password') 'whole runner resolves nested env values into the DTN file'
    $log = Get-Content (Join-Path $job ('{0:yyyyMMdd}.log' -f (Get-Date))) -Raw
    Check ($log -match 'End' -and $log -notmatch 'synthetic-user|synthetic-password') 'whole runner completes without logging the DTN credentials'
} finally {
    Remove-Item Env:DATAAGENT_INVOICE_TEST_USER -ErrorAction SilentlyContinue
    Set-Location $before
}
"PASS: $checks invoice checks; evidence: $root"
