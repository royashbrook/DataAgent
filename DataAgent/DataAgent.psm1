function Save-RunReceipt($Receipt, $Path) {
    $temp = "$Path.new"
    $Receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Get-StateDirectory($WorkingDirectory) {
    $feedPath = (Resolve-Path -LiteralPath $WorkingDirectory).ProviderPath
    $root = $env:DATAAGENT_STATE_ROOT
    if (!$root) { $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DataAgent' }
    if (![IO.Path]::IsPathFullyQualified($root)) { throw 'DATAAGENT_STATE_ROOT must be an absolute path.' }
    $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($feedPath))).ToLowerInvariant()
    Join-Path $root $key
}

function Get-DataAgentReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $WorkingDirectory)
    $directory = Get-StateDirectory $WorkingDirectory
    if (Test-Path -LiteralPath $directory) {
        Get-ChildItem -LiteralPath $directory -Filter '*.receipt.json' -File |
            Sort-Object LastWriteTimeUtc | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    }
}

function Clear-RunState($Directory, $KeepDays) {
    $cutoff = (Get-Date).AddDays(-$KeepDays)
    Get-ChildItem -LiteralPath $Directory -File | Where-Object {
        $_.Name -match '^[a-f0-9]{32}\.(receipt|recording)\.json(\.new)?$' -and $_.LastWriteTime -lt $cutoff
    } | Remove-Item -Force
}

function Invoke-DataAgent {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string] $SettingsPath,
        [ValidateSet('Mock', 'ExportOnly', 'Live')][string] $Mode = 'Mock',
        [string] $WorkingDirectory,
        [string] $FixturePath,
        [datetime] $RunAt = (Get-Date)
    )
    $ErrorActionPreference = 'Stop'
    $settings = (Resolve-Path -LiteralPath $SettingsPath).ProviderPath
    $cfg = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    # Config chooses known implementations, never arbitrary commands or evaluated expressions.
    if ($cfg.etl.source -cnotin @('sql', 'csv') -or $cfg.etl.format -cne 'csv' -or $cfg.etl.destination -cnotin @('email', 'recording')) {
        throw 'etl requires source sql/csv, format csv, and destination email/recording.'
    }
    $target = if ($WorkingDirectory) { $WorkingDirectory } elseif ($Mode -eq 'Live') { Split-Path -Parent $settings } else { 'a new temporary output directory' }
    if (!$PSCmdlet.ShouldProcess("$settings -> $target", "Run $Mode feed: retention, extraction, artifact and receipt writes; delivery only in Live/Mock")) { return }
    # One approval covers this run; nested adapters must not prompt halfway through it.
    $ConfirmPreference = 'None'
    if (!$WorkingDirectory) {
        $WorkingDirectory = if ($Mode -eq 'Live') { Split-Path -Parent $settings } else { [IO.Directory]::CreateTempSubdirectory('dataagent-').FullName }
    }
    if ($Mode -eq 'Mock') {
        if (!$FixturePath) { $FixturePath = Join-Path $PSScriptRoot 'synthetic.csv' }
        $sourcePath = (Resolve-Path -LiteralPath $FixturePath).ProviderPath
        $extract = { param($context) Import-Csv -LiteralPath $sourcePath }.GetNewClosure()
        $deliver = { param($context) Write-DataAgentRecording $context }
    } else {
        if ($FixturePath) { throw 'FixturePath is only valid in Mock mode.' }
        if ($cfg.etl.source -eq 'csv') {
            if (!$cfg.csv.path) { throw 'csv.path is required for a CSV source.' }
            $sourcePath = if ([IO.Path]::IsPathRooted($cfg.csv.path)) { $cfg.csv.path } else { Join-Path (Split-Path $settings) $cfg.csv.path }
            $sourcePath = (Resolve-Path -LiteralPath $sourcePath).ProviderPath
            if ((Split-Path $sourcePath) -eq (Resolve-Path -LiteralPath $WorkingDirectory).ProviderPath) {
                throw 'CSV source must be outside the output directory so retention cannot remove input.'
            }
            $extract = { param($context) Import-Csv -LiteralPath $sourcePath }.GetNewClosure()
        } else {
            if ($cfg.sql.InputFile -and ![IO.Path]::IsPathRooted($cfg.sql.InputFile)) {
                $cfg.sql.InputFile = Join-Path (Split-Path $settings) $cfg.sql.InputFile
            }
            $extract = { param($context) Invoke-DataAgentSql $context }
        }
        $deliver = if ($cfg.etl.destination -eq 'recording') {
            { param($context) Write-DataAgentRecording $context }
        } else { { param($context) Send-DataAgentMail $context } }
    }
    $runMode = if ($Mode -eq 'Live') { 'Run' } else { $Mode }
    Write-Information "DataAgent $Mode output: $WorkingDirectory" -InformationAction Continue
    Invoke-DataAgentPipeline -Config $cfg -WorkingDirectory $WorkingDirectory -RunAt $RunAt -Mode $runMode `
        -StateKeyDirectory (Split-Path -Parent $settings) `
        -Extract $extract -Transform { param($rows, $context) Export-DataAgentCsv $rows $context } -Deliver $deliver
}

function Invoke-DataAgentPipeline {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][object] $Config,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [Parameter(Mandatory)][scriptblock] $Extract,
        [Parameter(Mandatory)][scriptblock] $Transform,
        [scriptblock] $Deliver,
        [ValidateSet('ExportOnly', 'Run', 'Mock')][string] $Mode = 'ExportOnly',
        [datetime] $RunAt = (Get-Date),
        [string] $StateKeyDirectory
    )
    $ErrorActionPreference = 'Stop'
    if ($Mode -ne 'ExportOnly' -and !$Deliver) { throw 'Run/Mock requires a delivery adapter.' }
    $directory = Get-Item -LiteralPath $WorkingDirectory
    if (!$directory.PSIsContainer -or $directory.PSProvider.Name -ne 'FileSystem') {
        throw 'WorkingDirectory must be an existing filesystem directory dedicated to this feed.'
    }
    $cfg = $Config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $keepDays = 0
    if (![int]::TryParse([string]$cfg.keepdays, [ref]$keepDays) -or $keepDays -lt 1) {
        throw 'keepdays must be a positive integer before retention can run.'
    }
    $file = $cfg.file_format -f $RunAt
    if ([string]::IsNullOrWhiteSpace($file) -or $file -match '[/\\]' -or $file -in @('.', '..')) {
        throw 'file_format must resolve to a filename, not a path.'
    }
    if (!$PSCmdlet.ShouldProcess($directory.FullName, "Run $Mode pipeline: retention, callbacks, artifact and receipt writes")) { return }
    $ConfirmPreference = 'None'
    $id = [guid]::NewGuid().ToString('N')
    if (!$StateKeyDirectory) { $StateKeyDirectory = $directory.FullName }
    $stateDirectory = Get-StateDirectory $StateKeyDirectory
    $null = New-Item -ItemType Directory -Path $stateDirectory -Force
    $receiptPath = Join-Path $stateDirectory "$id.receipt.json"
    $logPath = Join-Path $directory.FullName ('{0:yyyyMMdd}.log' -f $RunAt)
    if ($file -eq [IO.Path]::GetFileName($logPath)) { throw 'Artifact filename collides with the daily log.' }
    $context = [pscustomobject]@{
        Config = $cfg
        RunAt = $RunAt
        RunId = $id
        Mode = $Mode
        StateDirectory = $stateDirectory
        ArtifactPaths = @(Join-Path $directory.FullName $file)
    }
    $context | Add-Member -MemberType ScriptProperty -Name ArtifactPath -Value { $this.ArtifactPaths[0] }
    $receipt = [ordered]@{
        schema = 2; runId = $id; mode = $Mode; status = 'started'
        stateDirectory = $stateDirectory
        workingDirectory = $directory.FullName
        startedAt = (Get-Date).ToUniversalTime().ToString('o')
        rowCount = 0; phases = [ordered]@{}; artifacts = @(); deliveries = @()
    }
    Push-Location -LiteralPath $directory.FullName
    try {
        # A new run never replaces evidence from an earlier attempt, even with a fixed clock.
        if (Test-Path -LiteralPath $context.ArtifactPath) { throw 'Artifact already exists. Choose a new filename or inspect the earlier run.' }
        Save-RunReceipt $receipt $receiptPath
        & {
            try {
                "`n`n"
                l 'Start'
                l 'Cleanup'
                $receipt.status = 'cleanup'
                Clear-RunState $stateDirectory $keepDays
                Clear-Files $cfg
                l 'Get Data'
                $receipt.status = 'extracting'
                $receipt.phases.extractStarted = (Get-Date).ToUniversalTime().ToString('o')
                Save-RunReceipt $receipt $receiptPath
                $rows = @(& $Extract $context | Where-Object { $null -ne $_ })
                $receipt.phases.extractEnded = (Get-Date).ToUniversalTime().ToString('o')
                $receipt.rowCount = $rows.Count
                if ($rows.Count -eq 0) {
                    $receipt.status = 'idle'
                    l 'No data available'
                    return
                }
                l 'Data Found. Formatting File.'
                $receipt.status = 'transforming'
                $receipt.phases.transformStarted = (Get-Date).ToUniversalTime().ToString('o')
                Save-RunReceipt $receipt $receiptPath
                $null = & $Transform $rows $context
                if (@($context.ArtifactPaths).Count -ne 1) { throw 'This candidate supports exactly one artifact per run.' }
                $artifact = Get-Item -LiteralPath $context.ArtifactPath
                if ($artifact.PSIsContainer -or $artifact.LinkType -or $artifact.Length -eq 0) {
                    throw 'Transform must write one nonempty regular artifact file.'
                }
                $receipt.artifacts = @([ordered]@{
                    name = $artifact.Name; bytes = $artifact.Length
                    sha256 = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                })
                $receipt.phases.transformEnded = (Get-Date).ToUniversalTime().ToString('o')
                l 'Use Data'
                if ($Mode -eq 'ExportOnly') {
                    $receipt.status = 'export-only'
                } else {
                    # An interrupted attempt is ambiguous. Never automatically retry a send.
                    $receipt.status = 'delivery-attempted'
                    $receipt.phases.deliverStarted = (Get-Date).ToUniversalTime().ToString('o')
                    Save-RunReceipt $receipt $receiptPath
                    $results = @(& $Deliver $context)
                    if ($results.Count -ne 1 -or $results[0] -isnot [System.Collections.IDictionary]) {
                        throw 'Delivery must return one outcome dictionary, not console output.'
                    }
                    $outcome = $results[0]
                    if ($outcome.state -notin @('submitted', 'confirmed') -or !$outcome.adapter -or !$outcome.destination) {
                        throw 'Delivery outcome needs adapter, effective destination, and submitted/confirmed state.'
                    }
                    if ($outcome.state -eq 'confirmed' -and !$outcome.acknowledgment) {
                        throw 'Confirmed requires an adapter acknowledgment.'
                    }
                    $deliveryRecord = [ordered]@{
                        adapter = $outcome.adapter; destination = $outcome.destination; state = $outcome.state
                        artifacts = @($receipt.artifacts[0].name)
                        mock = ($outcome.mock -eq $true)
                    }
                    if ($outcome.mock) {
                        $deliveryRecord.mockEvidence = @{ id = $outcome.id; acknowledgment = $outcome.acknowledgment }
                    } else {
                        if ($outcome.id) { $deliveryRecord.id = $outcome.id }
                        if ($outcome.acknowledgment) { $deliveryRecord.acknowledgment = $outcome.acknowledgment }
                    }
                    $receipt.deliveries = @($deliveryRecord)
                    $receipt.phases.deliverEnded = (Get-Date).ToUniversalTime().ToString('o')
                    $receipt.status = 'completed'
                }
                ''
                l 'End'
            } catch {
                $receipt.failedPhase = $receipt.status
                $receipt.status = 'error'
                # Keep the error in the daily log as well as the process exit path.
                $_.ToString()
                throw
            } finally {
                $receipt.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
                Save-RunReceipt $receipt $receiptPath
            }
        } *>&1 | Tee-Object -FilePath $logPath -Append | ForEach-Object {
            Write-Information $_ -InformationAction Continue
        }
    } finally {
        Pop-Location
    }
    [pscustomobject]$receipt
}

function Invoke-DataAgentSql {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)] $Context)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess('configured SQL connection', 'Execute configured SQL (not enforced read-only)')) { return }
    if ([string]::IsNullOrWhiteSpace($env:CONNECTION_STRING)) { throw 'CONNECTION_STRING is required.' }
    Import-Module SqlServer -RequiredVersion 22.4.5.1 -Cmdlet Invoke-Sqlcmd
    $sqlargs = $Context.Config.sql | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    if ($sqlargs.ContainsKey('ConnectionString')) { throw 'ConnectionString belongs in the environment, not settings.' }
    $sqlargs.ConnectionString = $env:CONNECTION_STRING
    try { Invoke-Sqlcmd @sqlargs -ErrorAction Stop }
    catch { throw 'SQL extraction failed. Inspect the database privately; connection details are not logged.' }
}

function Export-DataAgentCsv {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][object[]] $Rows, [Parameter(Mandatory)] $Context)
    if (!$PSCmdlet.ShouldProcess($Context.ArtifactPath, 'Export CSV')) { return }
    $columns = if ($Rows[0] -is [System.Data.DataRow]) {
        @($Rows[0].Table.Columns.ColumnName)
    } else {
        @($Rows[0].PSObject.Properties.Name)
    }
    $Rows | Select-Object -Property $columns | Export-Csv -LiteralPath $Context.ArtifactPath -NoTypeInformation -NoClobber
}

function Send-DataAgentMail {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)] $Context)
    $ErrorActionPreference = 'Stop'
    if ($Context.Mode -ne 'Run') { throw 'Mail delivery requires Run mode.' }
    if (!$PSCmdlet.ShouldProcess($Context.ArtifactPath, 'Submit file to configured mail recipients')) { return }
    if ([string]::IsNullOrWhiteSpace($env:CLIENT_SECRET)) { throw 'CLIENT_SECRET is required.' }
    $cfg = $Context.Config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    if ($cfg.msgraph.client_secret) { throw 'client_secret belongs in the environment, not settings.' }
    Import-Module Send-FileViaEmail -RequiredVersion 2.0.0.0 -ErrorAction Stop
    $cfg.msgraph.client_secret = $env:CLIENT_SECRET
    try { $null = Send-FileViaEmail ([IO.Path]::GetFileName($Context.ArtifactPath)) $cfg }
    catch { throw 'Email submission failed. Inspect the provider privately; credentials are not logged.' }
    @{ adapter = 'Send-FileViaEmail'; destination = $cfg.mail; state = 'submitted'; mock = $false }
}

function Write-DataAgentRecording {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)] $Context)
    if (!$PSCmdlet.ShouldProcess($Context.StateDirectory, 'Write mock delivery recording')) { return }
    $destination = @{ path = 'local-recording'; from = 'sender@example.invalid'; to = @('sink@example.invalid'); subject = 'Synthetic feed proof' }
    $record = @{
        mock = $true; destination = $destination
        attachment = [IO.Path]::GetFileName($Context.ArtifactPath)
        sha256 = (Get-FileHash -LiteralPath $Context.ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Context.StateDirectory "$($Context.RunId).recording.json") -Encoding utf8NoBOM
    @{ adapter = 'recording'; destination = $destination; state = 'confirmed'; mock = $true
        id = "mock-$($Context.RunId)"; acknowledgment = 'local recording written, no external delivery' }
}

Export-ModuleMember -Function Invoke-DataAgent, Get-DataAgentReceipt, Invoke-DataAgentPipeline, Invoke-DataAgentSql, Export-DataAgentCsv, Send-DataAgentMail, Write-DataAgentRecording
