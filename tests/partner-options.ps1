param([string] $ModulePath = "$PSScriptRoot/../DataAgent")
$ErrorActionPreference = 'Stop'
$ModulePath = (Resolve-Path $ModulePath).Path
$root = [IO.Directory]::CreateTempSubdirectory('dataagent-partners-').FullName
$before = Get-Location
$checks = 0
function Check($Condition, $Name) { if (!$Condition) { throw "FAIL: $Name" }; $script:checks++ }
function Format($Options) {
    $Options.Path = "$root/x12.txt"
    & "$ModulePath/fmt/x12-210.ps1" -Data $rows -Options $Options
    @(Get-Content -LiteralPath $Options.Path)
}
$rows = @(
    [pscustomobject]@{b302='B';b307=3;kind='D';note='present';ref='R*1';qty=2}
    [pscustomobject]@{b302='B';b307=3;kind='A';note='';ref='skip';qty=1}
)
$options = @{
    Values=@{now='2026-10-19T08:30:00'}
    Detail=@('kind','note','ref','qty')
    Control='1{now:yyMMdd}00'
    Dates=@{due=7}
    Separator='~';Terminator='!'
    Head=@('ISA*{control}','GS*{dates.due:yyyyMMdd}')
    Invoice=@('ST*{b302}')
    Line=@(
        'LX*{lx}'
        @{Text=@('N9*{ref}','L0*{qty}');When=@{Field='kind';Is='A';Not=$true}}
        @{Text='L1*{note}';When=@{Field='note'}}
        @{Text='L1*EMPTY';When=@{Field='note';Not=$true}}
    )
    Close=@('L3*{b307}')
    Se='SE*{se:0000000000}*{b302}'
    Tail=@('GE*1*{control}','IEA*{control}')
}
$lines = Format $options
$expected = @('ISA~126101900!','GS~20261026!','ST~B!','LX~1!','N9~R*1!','L0~2!','L1~present!','LX~2!','L1~EMPTY!','L3~3!','SE~0000000009~B!','GE~1~126101900!','IEA~126101900!')
$x12Expected = $expected
Check (($lines -join '|') -ceq ($expected -join '|')) 'conditional pairs, presence/absence, literal-only separators, terminators, dates, control and padded/fixed counts'
$other = @{} + $options
$other.Control = '{now:yy}{day:000}{now:HHmm}'
$lines = Format $other
Check ($lines[0] -ceq 'ISA~262920830!') 'day-of-year and time control scheme'
$other.Values = @{now='2026-10-19T08:30:00';control='EXPLICIT'}
$lines = Format $other
Check ($lines[0] -ceq 'ISA~EXPLICIT!') 'explicit control still wins over a computed scheme'
$other = @{} + $options
$other.SeDetailCount = 4
$other.SeExtra = 2
$lines = Format $other
Check ($lines[-3] -ceq 'SE~0000000013~B!') 'explicit legacy per-detail count and offset do not change emitted segments'
Check ($lines.Count -eq $expected.Count) 'legacy count override is not an extra segment'
$other = @{} + $options
$other.Remove('Control'); $other.Remove('Dates')
$lines = Format $other
$clock = [datetime]'2026-10-19T08:30:00'
$hour = [int]('{0:00}{1:0000}' -f $clock.ToString('yy'), ($clock - [datetime]::new(2026,1,1)).TotalHours)
Check ($lines[0] -ceq "ISA~$hour!") 'default hour control follows the configured filing clock'

try {
    Import-Module "$ModulePath/DataAgent.psd1" -Force
    Check ([IO.Path]::GetFullPath((Get-Command Invoke-DataAgent).Module.ModuleBase) -eq [IO.Path]::GetFullPath($ModulePath)) 'whole-runner checks invoke the requested source or saved package, not another installed copy'
    $data = @(
        [pscustomobject]@{id='B';amount=5;charge=2}
        [pscustomobject]@{id='B';amount=5;charge=3}
        [pscustomobject]@{id='A';amount=7;charge=7}
    )
    $data | ConvertTo-Json | Set-Content "$root/rows.json"
    'param($Data,$Options); Get-Content $Options.InputFile -Raw | ConvertFrom-Json' | Set-Content "$root/source.ps1"
    'param($Data,$Options); Get-Content $Data -Raw | Set-Content $Options.Path -NoNewline' | Set-Content "$root/destination.ps1"
    $config = @{
        directory=$root
        src=@{adapter='./source.ps1';args=@{InputFile='rows.json'}}
        fmt=@{
            adapter='pdi'
            args=@{Path='framed.txt';Key='id';Head=@('id','amount');Type='';H='';D='{id},{charge}';Footer='TOTAL,{id},{amount}';Values=@{now='2026-10-19T08:30:00'}}
            Prepend=@('run {now:yyyyMMdd}','sum {sum.invoices:0.00}')
            Append=@('done')
            Sum=@{invoices=@{Property='amount';UniqueBy='id'}}
        }
        dst=@{adapter='./destination.ps1';args=@{Path='seen.txt'}}
    }
    $null = Invoke-DataAgent $config
    $lines = @(Get-Content "$root/framed.txt")
    $expected = @('run 20261019','sum 12.00','B,2','B,3','TOTAL,B,5','A,7','TOTAL,A,7','done')
    Check (($lines -join '|') -ceq ($expected -join '|')) 'whole runner frames text, sums distinct invoices once and writes ordered per-invoice footers'
    Check ((Get-FileHash "$root/framed.txt").Hash -ceq (Get-FileHash "$root/seen.txt").Hash) 'destination reads the already-decorated artifact'
    $config.fmt.Sum.invoices.Remove('UniqueBy')
    $null = Invoke-DataAgent $config
    Check ((Get-Content "$root/framed.txt")[1] -ceq 'sum 17.00') 'omitting UniqueBy sums all rows'
    $config.fmt = @{adapter='csv';args=@{Path='plain.csv';Delimiter='*';UseQuotes='Never'};Prepend=@('REPORT');Append=@('END')}
    $null = Invoke-DataAgent $config
    $lines = @(Get-Content "$root/plain.csv")
    Check ($lines[0] -ceq 'REPORT' -and $lines[1] -ceq 'id*amount*charge' -and $lines[2] -ceq 'B*5*2' -and $lines[-1] -ceq 'END') 'CSV passthrough remains independent of format-wide framing'
    $config.fmt.args.NoHeader = $true
    $null = Invoke-DataAgent $config
    Check ((@(Get-Content "$root/plain.csv") -join '|') -ceq 'REPORT|B*5*2|B*5*3|A*7*7|END') 'CSV NoHeader passes through without affecting frames or source order'
    $rows | ConvertTo-Json | Set-Content "$root/x12-rows.json"
    $x12Options = @{} + $options
    $x12Options.Path = 'framed.x12'
    $jsonConfig = @{directory=$root;src=@{adapter='./source.ps1';args=@{InputFile='x12-rows.json'}};fmt=@{adapter='x12-210';args=$x12Options;Prepend='BEGIN';Append='END'}}
    $jsonConfig | ConvertTo-Json -Depth 12 | Set-Content "$root/settings.json"
    $null = Invoke-DataAgent "$root/settings.json"
    Check ((@(Get-Content "$root/framed.x12") -join '|') -ceq ((@('BEGIN') + $x12Expected + @('END')) -join '|')) 'JSON settings preserve conditional pairs, dates and frames through the actual resolver and runner'

    . "$ModulePath/fmt/text/frame.ps1"
    $path = "$root/no-newline.txt"
    Set-Content $path -Value 'body' -NoNewline
    Add-FormatFrame @{Append='tail'} $data @{Path=$path}
    Check ((Get-Content $path -Raw) -ceq ('body'+[Environment]::NewLine+'tail'+[Environment]::NewLine)) 'a body without a final newline is not joined to its append'
    $hash = (Get-FileHash $path).Hash
    Add-FormatFrame @{Prepend=@();Append=@()} $data @{Path=$path}
    Check ((Get-FileHash $path).Hash -ceq $hash) 'empty frames leave bytes alone'
    Set-Content $path -Value 'body' -Encoding unicode -NoNewline
    Add-FormatFrame @{Append='tail'} $data @{Path=$path;Encoding='unicode'}
    Check ((Get-Content $path -Raw -Encoding unicode) -ceq ('body'+[Environment]::NewLine+'tail'+[Environment]::NewLine)) 'framing honors the configured text encoding'
    $binary = "$root/binary.zip"
    Set-Content $binary -Value 'unchanged' -NoNewline
    $hash = (Get-FileHash $binary).Hash
    $error = $null
    try { Add-FormatFrame @{Prepend='bad'} $data @{Path=$binary} } catch { $error = $_ }
    Check ($error -and (Get-FileHash $binary).Hash -ceq $hash) 'ZIP framing refuses without changing artifact bytes'
    '[]' | Set-Content "$root/rows.json"
    $config.fmt.args.Path = 'idle.csv'
    Remove-Item "$root/seen.txt"
    $null = Invoke-DataAgent $config
    Check (!(Test-Path "$root/idle.csv") -and !(Test-Path "$root/seen.txt")) 'no data still means no framed file and no destination'
} finally { Set-Location $before }
"PASS: $checks partner checks; evidence: $root"
