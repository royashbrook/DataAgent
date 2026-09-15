$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$root = [IO.Directory]::CreateTempSubdirectory('dataagent-acceptance-').FullName
$env:DATAAGENT_STATE_ROOT = "$root/state"
$env:PSModulePath = (@($repo, "$repo/adapters", "$repo/testing", "$root/modules", $env:PSModulePath) -join [IO.Path]::PathSeparator)
$script:checks = 0
function Assert($Condition, $Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    $script:checks++
}
function Refuses($Action, $Pattern) {
    try { & $Action; throw 'accepted unexpectedly' } catch { Assert ($_.ToString() -match $Pattern) "refuses $Pattern" }
}
function Config($Name) {
    $null = New-Item -ItemType Directory "$root/$Name/output" -Force
    @{
        keepdays = 10; purgefiles = '*.csv,*.log'
        source = @{ module = 'DataAgent.Test'; version = '0.4.0'; command = 'Read-DataAgentFixture' }
        transform = @{ module = 'DataAgent.Csv'; version = '0.4.0'; command = 'Export-DataAgentCsv'; options = @{ file_format = 'test.csv' } }
        destination = @{ module = 'DataAgent.Test'; version = '0.4.0'; command = 'Write-DataAgentTestReceipt' }
    }
}
function Run($Name, $Config, [switch]$WhatIf) {
    $Config | ConvertTo-Json -Depth 12 | Set-Content "$root/$Name/settings.json"
    Invoke-DataAgent -SettingsPath "$root/$Name/settings.json" -WorkingDirectory "$root/$Name/output" -WhatIf:$WhatIf
}
function Module($Name, $Version, $Code) {
    $path = New-Item -ItemType Directory "$root/modules/$Name/$Version" -Force
    $Code | Set-Content "$path/$Name.psm1"
    New-ModuleManifest -Path "$path/$Name.psd1" -RootModule "$Name.psm1" -ModuleVersion $Version -FunctionsToExport '*' -PowerShellVersion 7.4
}

# Fake providers exist only in this test process. No real credentials or calls.
Module SqlServer 22.4.5.1 @'
function Invoke-Sqlcmd {
    param($ConnectionString, $InputFile, $Query, $OutputAs, $QueryTimeout)
    if ($ConnectionString -ne 'test-only') { throw 'unexpected connection' }
    if ($InputFile -and !(Test-Path -LiteralPath $InputFile)) { throw 'input not resolved' }
    $table = [Data.DataTable]::new()
    $null = $table.Columns.Add('B'); $null = $table.Columns.Add('A')
    $null = $table.Rows.Add('comma,value', 'quote"value')
    ,$table
}
'@
Module Send-FileViaEmail 2.0.0.0 @'
function Send-FileViaEmail($File, $Config) {
    if ($Config.msgraph.client_secret -ne 'test-only' -or !(Test-Path -LiteralPath $File)) { throw 'bad mail arguments' }
    if ([IO.Path]::GetFileName($File) -ne $File) { throw 'attachment name changed' }
}
'@
Import-Module DataAgent -RequiredVersion 0.4.0 -Force
Import-Module DataAgent.Test -RequiredVersion 0.4.0 -Force
$coreHash = (Get-FileHash "$repo/DataAgent/DataAgent.psm1").Hash
$receipt = Test-DataAgent
Assert ($receipt.status -eq 'completed' -and $receipt.rows -eq 5) 'test module runs real runner'
Assert ($receipt.artifacts.Count -eq 1 -and $receipt.deliveries[0].outcome.state -eq 'recorded') 'artifact and outcome lists'
Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | Export-Csv "$root/expected.csv" -NoTypeInformation
Assert ((Get-FileHash "$root/expected.csv").Hash -eq (Get-FileHash $receipt.artifacts[0].path).Hash) 'CSV byte parity including quotes and multiline fields'
$cfg = Config 'csv-source'
Copy-Item "$repo/testing/DataAgent.Test/synthetic.csv" "$root/csv-source/input.csv"
$cfg.source = @{ module = 'DataAgent.Csv'; version = '0.4.0'; command = 'Import-DataAgentCsv'; options = @{ path = 'input.csv' } }
$r = Run 'csv-source' $cfg
Assert ($r.rows -eq 5 -and (Get-FileHash $r.artifacts[0].path).Hash -eq (Get-FileHash "$root/expected.csv").Hash) 'CSV source resolves relative to config'
$cfg.source.options.path = 'output/test.csv'
Refuses { Run 'csv-source' $cfg } 'input must be outside'
$cfg = Config 'escape'; $cfg.transform.options.file_format = '../outside.csv'
Refuses { Run 'escape' $cfg } 'Invalid CSV filename'
$cfg = Config 'idle'; $cfg.source.options = @{ empty = $true }
$r = Run 'idle' $cfg
Assert ($r.status -eq 'idle' -and !$r.artifacts.Count -and !$r.deliveries.Count) 'idle skips remaining adapters'
$cfg = Config 'preview'; $cfg.source.module = 'ModuleThatDoesNotExist'
$null = Run 'preview' $cfg -WhatIf
Assert (!(Get-ChildItem "$root/preview/output")) 'WhatIf writes nothing and imports nothing'
$cfg = Config 'export'; $cfg.Remove('destination')
$r = Run 'export' $cfg
Assert ($r.status -eq 'completed' -and !$r.deliveries.Count) 'omit destination to export only'
$hash = (Get-FileHash $r.artifacts[0].path).Hash
(Get-Item $r.artifacts[0].path).LastWriteTime = (Get-Date).AddDays(-30)
Refuses { Run 'export' $cfg } 'output exists'
Assert ((Get-FileHash $r.artifacts[0].path).Hash -eq $hash) 'cleanup cannot erase colliding output'
Assert (@(Get-DataAgentReceipt -SettingsPath "$root/export/settings.json" | Where-Object status -eq error).Count -eq 1) 'error receipt persisted'
$cfg = Config 'cleanup'
'old' | Set-Content "$root/cleanup/output/old.csv"
'keep' | Set-Content "$root/cleanup/output/unrelated.txt"
(Get-Item "$root/cleanup/output/old.csv").LastWriteTime = (Get-Date).AddDays(-30)
$r = Run 'cleanup' $cfg
Assert (!(Test-Path "$root/cleanup/output/old.csv") -and (Test-Path "$root/cleanup/output/unrelated.txt") -and (Test-Path $r.artifacts[0].path)) 'scoped output retention'
$state = (Get-ChildItem "$root/state" -Recurse -Filter "$($r.runId).receipt.json").DirectoryName
$owned = "$state/$([guid]::NewGuid().ToString('N')).receipt.json"
'{}' | Set-Content $owned; '{}' | Set-Content "$state/unrelated.json"
(Get-Item $owned).LastWriteTime = (Get-Date).AddDays(-30)
$cfg.source.options = @{ empty = $true }; $null = Run 'cleanup' $cfg
Assert (!(Test-Path $owned) -and (Test-Path "$state/unrelated.json")) 'scoped receipt retention'
$cfg = Config 'failure'; $cfg.destination.options = @{ fail = $true }
$location = (Get-Location).Path
Refuses { Run 'failure' $cfg } 'synthetic destination failure'
$r = @(Get-DataAgentReceipt -SettingsPath "$root/failure/settings.json")[-1]
Assert ($r.status -eq 'error' -and $r.adapter -eq 'DataAgent.Test\Write-DataAgentTestReceipt' -and !$r.deliveries.Count) 'failure names command without claiming delivery'
Assert ((Get-Location).Path -eq $location) 'location restored'
$cfg = Config 'sql-mail'
'select 1' | Set-Content "$root/sql-mail/input.sql"
$cfg.source = @{ module = 'DataAgent.Sql'; version = '0.4.0'; command = 'Invoke-DataAgentSql'; options = @{ InputFile = 'input.sql'; OutputAs = 'DataTables' } }
$cfg.destination = @{ module = 'DataAgent.Mail'; version = '0.4.0'; command = 'Send-DataAgentMail'; options = @{ mail = @{ to = @('example@example.invalid') }; msgraph = @{} } }
$env:CONNECTION_STRING = 'test-only'; $env:CLIENT_SECRET = 'test-only'
$r = Run 'sql-mail' $cfg
Assert ($r.rows -eq 1 -and $r.deliveries[0].outcome.state -eq 'submitted') 'DataTable rows and mail submission'
Assert ((Get-Content $r.artifacts[0].path -First 1) -eq '"B","A"') 'DataTable column order'
$cfg.source.options.ConnectionString = 'not-allowed'
Refuses { Run 'sql-mail' $cfg } 'ConnectionString'
$cfg.source.options.Remove('ConnectionString'); $env:CONNECTION_STRING = ''
Refuses { Run 'sql-mail' $cfg } 'CONNECTION_STRING'
$env:CLIENT_SECRET = ''; $env:CONNECTION_STRING = ''

# An independently installed module adds formats/destinations with no core edits.
Module OutsideAdapter 1.0.0 @'
function Get-Outside($Data, $Options, $Context) { [pscustomobject]@{ id = 1 }; [pscustomobject]@{ id = 2 } }
function Export-Outside($Data, $Options, $Context) {
    foreach ($name in @('first.json', 'second.json')) {
        $path = Join-Path $Context.directory $name
        $Data | ConvertTo-Json | Set-Content -LiteralPath $path
        Get-Item -LiteralPath $path
    }
}
function Send-Outside($Data, $Options, $Context) {
    if ($Options.fail) { throw 'second destination failed' }
    foreach ($file in $Data) { @{ state = 'confirmed'; acknowledgment = 'test-only'; path = $file.FullName } }
}
function Send-NoAck($Data, $Options, $Context) { @{ state = 'confirmed' } }
function Export-Bad($Data, $Options, $Context) { 'not a file' }
'@
$cfg = Config 'extension'; $cfg.transform = @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Export-Outside' }
$cfg.source = @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Get-Outside' }
$dest = @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Send-Outside' }
$cfg.destination = @($dest, $dest)
$r = Run 'extension' $cfg
Assert ($r.rows -eq 2 -and $r.artifacts.Count -eq 2 -and $r.deliveries.Count -eq 4) 'external source and formatter, two files, two destinations'
Assert ((Get-FileHash "$repo/DataAgent/DataAgent.psm1").Hash -eq $coreHash) 'extension leaves core bytes unchanged'
$cfg = Config 'partial'; $cfg.transform = @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Export-Outside' }
$cfg.destination = @($dest, @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Send-Outside'; options = @{ fail = $true } })
Refuses { Run 'partial' $cfg } 'second destination failed'
$r = @(Get-DataAgentReceipt -SettingsPath "$root/partial/settings.json")[-1]
Assert ($r.status -eq 'error' -and $r.deliveries.Count -eq 2) 'prior destination outcomes survive later failure'
$cfg = Config 'no-ack'; $cfg.destination = @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Send-NoAck' }
Refuses { Run 'no-ack' $cfg } 'confirmed requires acknowledgment'
$cfg = Config 'bad-file'; $cfg.transform = @{ module = 'OutsideAdapter'; version = '1.0.0'; command = 'Export-Bad' }
Refuses { Run 'bad-file' $cfg } 'nonempty regular FileInfo'
$cfg = Config 'missing-export'; $cfg.source.command = 'NotExported'
Refuses { Run 'missing-export' $cfg } 'Adapter not exported'

$packages = @("$repo/DataAgent") + @(Get-ChildItem "$repo/adapters", "$repo/testing" -Directory).FullName
foreach ($package in $packages) {
    $name = Split-Path $package -Leaf
    $manifest = Test-ModuleManifest "$package/$name.psd1"
    Assert ($manifest.Version -eq '0.4.0') "$name manifest"
    foreach ($command in $manifest.ExportedFunctions.Keys) { Assert ($null -ne (Get-Verb ($command -split '-')[0])) "$command approved verb" }
    $staged = New-Item -ItemType Directory "$root/staged/$name/0.4.0" -Force
    foreach ($file in $manifest.FileList) { Copy-Item $file $staged }
    Assert (Test-Path "$staged/$name.psm1") "$name package"
}
$env:PSModulePath = (@("$root/staged", "$root/modules", "$PSHOME/Modules") -join [IO.Path]::PathSeparator)
Remove-Module DataAgent* -Force
Import-Module DataAgent.Test -RequiredVersion 0.4.0
$r = Test-DataAgent
Assert ($r.rows -eq 5 -and $r.status -eq 'completed') 'staged packages run without checkout-only files'
"PASS: $script:checks checks; evidence: $root"
