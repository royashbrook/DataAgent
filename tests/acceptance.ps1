param(
    [string] $BundlePath = "$PSScriptRoot/fixtures",
    [string] $DependencyPath,
    [string] $OutputDirectory,
    [switch] $FailureChild
)
$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'
if ($DependencyPath) { $env:PSModulePath = $DependencyPath + [IO.Path]::PathSeparator + $env:PSModulePath }
$manifest = "$PSScriptRoot/../DataAgent/DataAgent.psd1"
Import-Module $manifest -Force
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
$cfg = Get-Content -LiteralPath "$bundle/settings.scrubbed.json" -Raw | ConvertFrom-Json
$runAt = [datetime]'2026-09-11T12:00:00'
$transform = { param($rows, $context) Export-DataAgentCsv $rows $context }
$record = { param($context) Write-DataAgentRecording $context }
if ($FailureChild) {
    Invoke-DataAgentPipeline -Config $cfg -WorkingDirectory $OutputDirectory -RunAt $runAt `
        -Extract { throw 'synthetic source failure' } -Transform $transform
    exit 0
}
if (!$OutputDirectory) { $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('dataagent-proof-' + [guid]::NewGuid().ToString('N')) }
$null = New-Item -ItemType Directory -Path $OutputDirectory
$env:DATAAGENT_STATE_ROOT = Join-Path $OutputDirectory 'state'
$checks = [Collections.Generic.List[string]]::new()
$startLocation = (Get-Location).Path
function Assert($Condition, $Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    $checks.Add($Name)
}
function New-Case($Name) { (New-Item -ItemType Directory -Path (Join-Path $OutputDirectory $Name)).FullName }
function Receipt($Directory) { @(Get-DataAgentReceipt -WorkingDirectory $Directory)[-1] }
$objects = @(Import-Csv -LiteralPath "$bundle/sample/synthetic-rows.csv")
$table = [Data.DataTable]::new()
foreach ($column in $objects[0].PSObject.Properties.Name) { $null = $table.Columns.Add($column, [string]) }
foreach ($obj in $objects) {
    $row = $table.NewRow()
    foreach ($column in $table.Columns.ColumnName) { $row[$column] = $obj.$column }
    $table.Rows.Add($row)
}
$extract = { param($context) $table }.GetNewClosure()
$data = New-Case 'data'
Invoke-DataAgentPipeline $cfg $data $extract $transform $record -Mode Run -RunAt $runAt | Out-Null
$receipt = Receipt $data
$artifact = Join-Path $data $receipt.artifacts[0].name
$baseline = Join-Path $OutputDirectory 'baseline.csv'
$table | Select-Object $table.Columns.ColumnName | Export-Csv -LiteralPath $baseline -NoTypeInformation
Assert ((Get-FileHash $baseline).Hash -eq (Get-FileHash $artifact).Hash) 'DataTable artifact byte-identical to legacy Export-Csv'
Assert ($receipt.rowCount -eq 5) 'five rows, including quote and multiline fields'
Assert ($receipt.deliveries[0].mock -and !$receipt.deliveries[0].PSObject.Properties['id'] -and $receipt.deliveries[0].mockEvidence.id.StartsWith('mock-')) 'mock ID cannot appear as a real delivery ID'
Assert ($receipt.deliveries[0].destination.to[0] -eq 'sink@example.invalid' -and $receipt.deliveries[0].destination.to[0] -ne $cfg.mail.to[0]) 'receipt records effective destination override'
$recording = Get-Content -LiteralPath (Join-Path $receipt.stateDirectory "$($receipt.runId).recording.json") -Raw | ConvertFrom-Json
Assert ($recording.sha256 -eq $receipt.artifacts[0].sha256 -and $recording.attachment -eq $receipt.artifacts[0].name) 'recording sink binds attachment name and bytes'
Assert ($receipt.status -eq 'completed' -and $receipt.deliveries[0].state -eq 'confirmed') 'mock acknowledgment recorded explicitly'
Assert ($receipt.phases.extractEnded -and $receipt.phases.transformEnded -and $receipt.phases.deliverEnded) 'phase timestamps recorded'

$idle = New-Case 'idle'
$idleResult = @(Invoke-DataAgentPipeline $cfg $idle { param($context) } $transform { throw 'must not deliver' } -Mode Run -RunAt $runAt)
Assert ($idleResult.Count -eq 1 -and $idleResult[0].status -eq 'idle' -and $idleResult[0].finishedAt) 'idle returns exactly one finalized receipt, not log strings'
Assert ((Receipt $idle).status -eq 'idle' -and @(Get-ChildItem $idle -Filter '*.csv').Count -eq 0) 'empty input writes no artifact and never delivers'

$dry = New-Case 'dry'
Invoke-DataAgentPipeline $cfg $dry $extract $transform { throw 'dry-run must never deliver' } -RunAt $runAt | Out-Null
Assert ((Receipt $dry).status -eq 'dry-run' -and !(Receipt $dry).deliveries.Count) 'default dry-run writes artifact but skips the supplied delivery adapter'

$retention = New-Case 'retention'
$old = Join-Path $retention 'old.csv'
'synthetic old artifact' | Set-Content -LiteralPath $old
(Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-11)
$recent = Join-Path $retention 'recent.csv'
'synthetic recent artifact' | Set-Content -LiteralPath $recent
Invoke-DataAgentPipeline $cfg $retention { param($context) } $transform -RunAt $runAt | Out-Null
Assert (!(Test-Path $old) -and (Test-Path $recent)) 'real Clear-Files purges eleven-day-old file and keeps recent file'

$failure = New-Case 'failure'
$childArgs = @('-NoLogo', '-NoProfile', '-File', $PSCommandPath, '-BundlePath', $bundle, '-OutputDirectory', $failure, '-FailureChild')
if ($DependencyPath) { $childArgs += @('-DependencyPath', $DependencyPath) }
& (Join-Path $PSHOME 'pwsh') @childArgs *> (Join-Path $OutputDirectory 'failure-process.log')
$code = $LASTEXITCODE
Assert ($code -ne 0 -and (Receipt $failure).status -eq 'error') 'source exception reaches nonzero process exit and error receipt'
Assert ((Get-Content "$failure/20260911.log" -Raw).Contains('synthetic source failure')) 'source exception text reaches daily log'

$submitted = New-Case 'submitted'
Invoke-DataAgentPipeline $cfg $submitted $extract $transform {
    param($context)
    @{ adapter = 'offline-submission-stub'; destination = 'local-only'; state = 'submitted'; mock = $true }
} -Mode Run -RunAt $runAt | Out-Null
Assert ((Receipt $submitted).deliveries[0].state -eq 'submitted' -and !(Receipt $submitted).deliveries[0].PSObject.Properties['id']) 'return without acknowledgment stays submitted with no real ID'

foreach ($case in @('transform-error', 'deliver-error', 'invalid-receipt')) {
    $dir = New-Case $case
    $format = if ($case -eq 'transform-error') { { throw 'synthetic transform failure' } } else { $transform }
    $sink = if ($case -eq 'invalid-receipt') {
        { @{ adapter = 'bad-stub'; destination = 'local-only'; state = 'confirmed' } }
    } else { { throw 'synthetic delivery failure' } }
    $threw = $false
    try { Invoke-DataAgentPipeline $cfg $dir $extract $format $sink -Mode Run -RunAt $runAt | Out-Null } catch { $threw = $true }
    Assert ($threw -and (Receipt $dir).status -eq 'error') "$case refuses success"
}
$before = (Get-FileHash $artifact).Hash
$threw = $false
try { Invoke-DataAgentPipeline $cfg $data $extract $transform $record -Mode Run -RunAt $runAt | Out-Null } catch { $threw = $true }
Assert ($threw -and (Get-FileHash $artifact).Hash -eq $before) 'same-filename rerun refuses overwrite and resend'
Assert ((Test-ModuleManifest $manifest).Version -eq [version]'0.3.0') 'manifest imports pinned dependencies'

$emptyTable = $table.Clone()
$emptyExtract = { param($context) $emptyTable }.GetNewClosure()
$emptyDir = New-Case 'empty-table'
Invoke-DataAgentPipeline $cfg $emptyDir $emptyExtract $transform { throw 'empty table cannot deliver' } -Mode Run -RunAt $runAt | Out-Null
Assert ((Receipt $emptyDir).status -eq 'idle') 'empty DataTable is idle, not one empty row'
$nullDir = New-Case 'null-input'
Invoke-DataAgentPipeline $cfg $nullDir { $null } $transform { throw 'null cannot deliver' } -Mode Run -RunAt $runAt | Out-Null
Assert ((Receipt $nullDir).status -eq 'idle') 'null source result is idle'
$one = New-Case 'one-row'
$oneRow = { param($context) $table.Rows[0] }.GetNewClosure()
Invoke-DataAgentPipeline $cfg $one $oneRow $transform -RunAt $runAt | Out-Null
Assert ((Receipt $one).rowCount -eq 1 -and @(Import-Csv (Join-Path $one (Receipt $one).artifacts[0].name)).Count -eq 1) 'single DataRow stays one row with data columns only'
$json = New-Case 'json'
$jsonCfg = $cfg | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$jsonCfg.file_format = '{0:yyyyMMddHHmmss}.json'
Invoke-DataAgentPipeline $jsonCfg $json { [pscustomobject]@{ value = 'synthetic' } } {
    param($rows, $context)
    $rows | ConvertTo-Json | Set-Content -LiteralPath $context.ArtifactPath
} $record -Mode Run -RunAt $runAt | Out-Null
Assert ((Get-Content (Join-Path $json (Receipt $json).artifacts[0].name) -Raw | ConvertFrom-Json).value -eq 'synthetic') 'a non-SQL source and JSON formatter use the same lifecycle'
Assert ($cfg.msgraph.client_secret -eq '' -and $cfg.mail.to[0] -eq 'recipient@example.invalid') 'caller settings unchanged'
foreach ($name in @('../escape.csv', '20260911.log')) {
    $invalidCfg = $cfg | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $invalidCfg.file_format = $name
    $threw = $false
    try { Invoke-DataAgentPipeline $invalidCfg $dry $extract $transform -RunAt $runAt | Out-Null } catch { $threw = $true }
    Assert $threw "unsafe artifact name refused: $name"
}
$invalidCfg = $cfg | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$invalidCfg.keepdays = -1
$threw = $false
try { Invoke-DataAgentPipeline $invalidCfg $dry $extract $transform -RunAt $runAt | Out-Null } catch { $threw = $true }
Assert $threw 'invalid retention refuses before cleanup'
Assert ((Get-Location).Path -eq $startLocation) 'working directory restored after success and failure'

$stage = New-Case 'package'
$package = New-Item -ItemType Directory -Path "$stage/DataAgent/0.3.0"
foreach ($file in (Import-PowerShellDataFile $manifest).FileList) {
    Copy-Item -LiteralPath (Join-Path "$PSScriptRoot/../DataAgent" $file) -Destination $package.FullName
}
$env:PSModulePath = $stage + [IO.Path]::PathSeparator + $env:PSModulePath
Remove-Module DataAgent
Import-Module DataAgent -RequiredVersion 0.3.0
Assert ((Get-Module DataAgent).ModuleBase -eq $package.FullName -and @(Get-Command -Module DataAgent).Count -eq 7) 'manifest-only staged package imports by exact version'
$demo = New-Case 'demo'
Copy-Item "$PSScriptRoot/../examples/job.ps1", "$PSScriptRoot/../examples/settings.json" -Destination $demo
& (Join-Path $PSHOME 'pwsh') -NoLogo -NoProfile -File "$demo/job.ps1" *> (Join-Path $OutputDirectory 'demo-process.log')
Assert ($LASTEXITCODE -eq 0 -and (Receipt $demo).deliveries[0].mock -and (Receipt $demo).rowCount -eq 5) 'three-line job executes in a fresh process with packaged mock data'
Assert (@(Get-ChildItem $demo -File).Count -eq 2) 'mock consumer remains exactly settings and job, no generated files'
Assert ((Receipt $demo).mode -eq 'Mock') 'mock runs cannot be mistaken for live runs in receipts'
Assert ($receipt.artifacts -is [array] -and $receipt.deliveries -is [array]) 'singleton artifact and delivery remain JSON arrays'
Assert ((Receipt $idle).artifacts -is [array] -and (Receipt $idle).artifacts.Count -eq 0 -and (Receipt $idle).deliveries.Count -eq 0) 'idle artifact and delivery lists remain empty arrays'
Assert (@(Get-ChildItem $data -File -Filter '*.json').Count -eq 0) 'receipts and mock recordings stay outside feed output directory'

$retainedState = (Receipt $retention).stateDirectory
$oldReceipt = Join-Path $retainedState ('a' * 32 + '.receipt.json')
$oldRecording = Join-Path $retainedState ('a' * 32 + '.recording.json')
$unowned = Join-Path $retainedState 'unrelated.json'
foreach ($path in @($oldReceipt, $oldRecording, $unowned)) {
    '{}' | Set-Content -LiteralPath $path
    (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-11)
}
$recentReceipt = @(Get-ChildItem $retainedState -Filter '*.receipt.json' | Where-Object Name -ne ([IO.Path]::GetFileName($oldReceipt)))[0].FullName
Invoke-DataAgentPipeline $cfg $retention { } $transform -RunAt $runAt | Out-Null
Assert (!(Test-Path $oldReceipt) -and !(Test-Path $oldRecording)) 'shared retention purges owned old receipts and recordings without config changes'
Assert ((Test-Path $recentReceipt) -and (Test-Path $unowned)) 'shared retention keeps recent receipts and unrelated files'

function Save-Settings($Path, $Config) { $Config | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path }
$configDir = New-Case 'config-dispatch'
$configured = Get-Content "$PSScriptRoot/../examples/settings.json" -Raw | ConvertFrom-Json
$configured.etl.source = 'csv'
$configured.etl.destination = 'recording'
$configured | Add-Member -NotePropertyName csv -NotePropertyValue @{ path = "$bundle/sample/synthetic-rows.csv" }
$settingsFile = Join-Path $configDir 'settings.json'
Save-Settings $settingsFile $configured
$settingsHash = (Get-FileHash $settingsFile).Hash
$jobResult = @(Invoke-DataAgent -SettingsPath $settingsFile -Mode Live -RunAt $runAt)
$configuredReceipt = Receipt $configDir
Assert ($jobResult.Count -eq 1 -and $jobResult[0].status -eq 'completed') 'high-level job returns exactly one structured receipt'
# Apply the same JSON reader to both sides, including its automatic timestamp conversion.
$returnedJson = $jobResult[0] | ConvertTo-Json -Depth 12 | ConvertFrom-Json | ConvertTo-Json -Depth 12 -Compress
Assert ($returnedJson -ceq ($configuredReceipt | ConvertTo-Json -Depth 12 -Compress)) 'returned receipt matches the persisted finalized receipt'
Assert ($configuredReceipt.rowCount -eq 5 -and $configuredReceipt.deliveries[0].adapter -eq 'recording') 'config dispatch runs CSV source and local recording destination without custom code'
Assert ($configuredReceipt.artifacts[0].sha256 -eq $receipt.artifacts[0].sha256) 'config-dispatched artifact matches the same legacy fixture bytes'
Assert ((Get-FileHash $settingsFile).Hash -eq $settingsHash) 'config-driven job never rewrites settings'

$configured.etl.destination = 'email'
Save-Settings $settingsFile $configured
$dryResult = @(Invoke-DataAgent -SettingsPath $settingsFile -Mode DryRun -RunAt $runAt)
Assert ($dryResult.Count -eq 1 -and $dryResult[0].status -eq 'dry-run' -and $dryResult[0].finishedAt) 'DryRun returns exactly one finalized receipt'
Assert ((Receipt $configDir).status -eq 'dry-run' -and (Receipt $configDir).deliveries.Count -eq 0) 'configured email is not invoked by DryRun'
Assert (@(Get-ChildItem $configDir -Filter '*.csv').Count -eq 1) 'DryRun defaults to temporary output, not the live output directory'

$configured.csv.path = 'missing-input.csv'
Save-Settings $settingsFile $configured
Invoke-DataAgent -SettingsPath $settingsFile -Mode Mock -RunAt $runAt | Out-Null
Assert ((Receipt $configDir).rowCount -eq 5 -and (Receipt $configDir).deliveries[0].mock) 'Mock ignores configured source and destination and uses packaged synthetic data'

$invalidDir = New-Case 'invalid-adapter'
$configured.etl.source = 'sql; throw 123'
$invalidPath = Join-Path $invalidDir 'settings.json'
Save-Settings $invalidPath $configured
$threw = $false
try { Invoke-DataAgent -SettingsPath $invalidPath | Out-Null } catch { $threw = $true }
Assert ($threw -and @(Get-ChildItem $invalidDir).Count -eq 1 -and @(Get-DataAgentReceipt $invalidDir).Count -eq 0) 'unknown adapter rejected before execution or output mutation'

$inputGuard = New-Case 'input-guard'
$localSource = Join-Path $inputGuard 'input.csv'
Copy-Item "$bundle/sample/synthetic-rows.csv" $localSource
(Get-Item $localSource).LastWriteTime = (Get-Date).AddDays(-11)
$configured.etl.source = 'csv'
$configured.etl.destination = 'recording'
$configured.csv.path = 'input.csv'
$localSettings = Join-Path $inputGuard 'settings.json'
Save-Settings $localSettings $configured
$threw = $false
try { Invoke-DataAgent -SettingsPath $localSettings -Mode Live | Out-Null } catch { $threw = $true }
Assert ($threw -and (Test-Path $localSource)) 'CSV input cannot share a retention-cleaned output directory'

$multiple = New-Case 'multi-refusal'
$threw = $false
try {
    Invoke-DataAgentPipeline $cfg $multiple $extract {
        param($rows, $context)
        $context.ArtifactPaths = @('one.csv', 'two.csv')
    } { throw 'must not deliver' } -Mode Run | Out-Null
} catch { $threw = $true }
Assert ($threw -and (Receipt $multiple).failedPhase -eq 'transforming') 'list-shaped schema does not falsely claim multi-artifact execution'
Assert ((Receipt $multiple).deliveries.Count -eq 0) 'rejected multi-artifact format leaves delivery list empty'

$portable = Join-Path $OutputDirectory 'portable'
& "$PSScriptRoot/../prepare.ps1" -OutputDirectory $portable -DependencyPath $DependencyPath | Out-Null
$savedModulePath = $env:PSModulePath
try {
    $env:PSModulePath = ''
    & (Join-Path $PSHOME 'pwsh') -NoLogo -NoProfile -File "$portable/try.ps1" *> (Join-Path $OutputDirectory 'portable.log')
    Assert ($LASTEXITCODE -eq 0) 'staged bundle runs in a fresh process without the developer module search path'
} finally { $env:PSModulePath = $savedModulePath }
Assert (@(Get-ChildItem "$portable/consumer" -File).Count -eq 2) 'portable consumer is only config plus three-line job'
$savedStateRoot = $env:DATAAGENT_STATE_ROOT
try {
    $env:DATAAGENT_STATE_ROOT = 'relative-state'
    $threw = $false
    try { Get-DataAgentReceipt $demo | Out-Null } catch { $threw = $true }
    Assert $threw 'relative state root refuses instead of changing meaning with working directory'
} finally { $env:DATAAGENT_STATE_ROOT = $savedStateRoot }
$proof = [ordered]@{
    status = 'pass'; checks = $checks; powershell = $PSVersionTable.PSVersion.ToString()
    platform = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    modules = @(Get-Module DataAgent,Add-PrefixForLogging,Clear-Files | Select-Object Name,@{n='Version';e={$_.Version.ToString()}})
    sourceSha256 = (Get-FileHash "$PSScriptRoot/../DataAgent/DataAgent.psm1").Hash.ToLowerInvariant()
    testSha256 = (Get-FileHash $PSCommandPath).Hash.ToLowerInvariant()
    fixtureSha256 = (Get-FileHash "$bundle/sample/synthetic-rows.csv").Hash.ToLowerInvariant()
    artifactSha256 = $receipt.artifacts[0].sha256
    outputDirectory = $OutputDirectory
    boundaries = @('synthetic source and local recording only', 'SQL and email not contacted', 'CSV newline matches native Export-Csv on the executing OS', 'no live feed migration')
}
$proof | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$OutputDirectory/proof.json" -Encoding utf8NoBOM
"PASS: $($checks.Count) checks. $OutputDirectory/proof.json"
