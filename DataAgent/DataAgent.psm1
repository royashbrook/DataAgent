function Get-StatePath($Path) {
    $root = $env:DATAAGENT_STATE_ROOT
    if (!$root) { $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DataAgent' }
    if (![IO.Path]::IsPathFullyQualified($root)) { throw 'DATAAGENT_STATE_ROOT must be absolute.' }
    $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Path)))
    Join-Path $root $key.ToLowerInvariant()
}

function Save-Receipt($Receipt, $Path) {
    $Receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$Path.new" -Encoding utf8NoBOM
    Move-Item -LiteralPath "$Path.new" -Destination $Path -Force
}

function Write-RunLog($Path, $Adapter, $Status) {
    $line = '{0:o} {1} {2}' -f (Get-Date), $Adapter, $Status
    Add-Content -LiteralPath $Path -Value $line
    Write-Information $line -InformationAction Continue
}

function Clear-Output($Config, $Directory, $Protected) {
    $patterns = @($Config.purgefiles -split ',' | Where-Object { $_ })
    Get-ChildItem -LiteralPath $Directory -File | Where-Object {
        $file = $_
        $file.FullName -notin $Protected -and $file.LastWriteTime -lt (Get-Date).AddDays(-$Config.keepdays) -and
            @($patterns | Where-Object { $file.Name -like $_ }).Count
    } | Remove-Item -Force
}

function Get-DataAgentReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $SettingsPath)
    $path = Get-StatePath (Resolve-Path -LiteralPath $SettingsPath).ProviderPath
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Filter '*.receipt.json' -File | Sort-Object LastWriteTimeUtc |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    }
}

function Invoke-DataAgent {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([Parameter(Mandatory)][string] $SettingsPath, [string] $WorkingDirectory, [datetime] $RunAt = (Get-Date))
    $ErrorActionPreference = 'Stop'
    $settings = (Resolve-Path -LiteralPath $SettingsPath).ProviderPath
    $cfg = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json -AsHashtable
    if (!$WorkingDirectory) { $WorkingDirectory = Split-Path $settings }
    $directory = Get-Item -LiteralPath $WorkingDirectory
    if (!$directory.PSIsContainer) { throw 'WorkingDirectory must be an existing directory.' }
    $keep = 0
    if (![int]::TryParse([string]$cfg.keepdays, [ref]$keep) -or $keep -lt 1) { throw 'keepdays must be positive.' }
    $steps = @(@{ role = 'source'; spec = $cfg.source }, @{ role = 'transform'; spec = $cfg.transform })
    foreach ($destination in @($cfg.destination)) {
        if ($null -ne $destination) { $steps += @{ role = 'destination'; spec = $destination } }
    }
    foreach ($step in $steps) {
        $s = $step.spec
        if (!$s.module -or !$s.version -or !$s.command -or ($s.options -and $s.options -isnot [hashtable])) { throw "$($step.role): invalid adapter descriptor." }
    }
    if (!$PSCmdlet.ShouldProcess($directory.FullName, 'Invoke-DataAgent: cleanup, configured adapters, receipts')) { return }
    $ConfirmPreference = 'None'
    # Import only explicitly selected modules; imports are executable code, too.
    foreach ($step in $steps) {
        $module = Import-Module $step.spec.module -RequiredVersion $step.spec.version -PassThru -ErrorAction Stop
        $step.command = $module.ExportedCommands[$step.spec.command]
        if (!$step.command) { throw "Adapter not exported: $($step.spec.module)\$($step.spec.command)" }
    }
    $state = Get-StatePath $settings
    $null = New-Item -ItemType Directory -Path $state -Force
    $id = [guid]::NewGuid().ToString('N')
    $path = Join-Path $state "$id.receipt.json"
    $log = Join-Path $directory.FullName ('{0:yyyyMMdd}.log' -f $RunAt)
    $context = @{ runId = $id; runAt = $RunAt; directory = $directory.FullName; configDirectory = Split-Path $settings; stateDirectory = $state }
    $receipt = [ordered]@{ schema = 3; runId = $id; startedAt = (Get-Date).ToString('o'); status = 'running'; adapter = ''; rows = 0; artifacts = @(); deliveries = @() }
    $data = @(); $artifacts = @()
    Push-Location -LiteralPath $directory.FullName
    try {
        Get-ChildItem -LiteralPath $state -File | Where-Object {
            $_.Name -match '^[a-f0-9]{32}\.receipt\.json(\.new)?$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-$keep)
        } | Remove-Item -Force
        :run foreach ($step in $steps) {
            $receipt.adapter = "$($step.spec.module)\$($step.spec.command)"
            Save-Receipt $receipt $path
            Write-RunLog $log $receipt.adapter 'start'
            $options = if ($step.spec.options) { $step.spec.options } else { @{} }
            $inputData = if ($step.role -eq 'destination') { $artifacts } else { $data }
            $result = @(& $step.command -Data @($inputData) -Options $options -Context $context)
            switch ($step.role) {
                source {
                    $data = @($result | Where-Object { $null -ne $_ })
                    $receipt.rows = $data.Count
                    if (!$data.Count) {
                        Clear-Output $cfg $directory.FullName @($settings, $log)
                        $receipt.status = 'idle'; break run
                    }
                }
                transform {
                    $artifacts = @($result)
                    foreach ($file in $artifacts) {
                        if ($file -isnot [IO.FileInfo] -or !$file.Exists -or $file.LinkType -or !$file.Length) { throw 'Transform must return nonempty regular FileInfo objects.' }
                        $receipt.artifacts += @{ path = $file.FullName; bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() }
                    }
                    # Never delete an existing target before its formatter can refuse overwrite.
                    Clear-Output $cfg $directory.FullName (@($settings, $log) + @($artifacts.FullName))
                    if (!$artifacts.Count) { $receipt.status = 'idle'; break run }
                }
                destination {
                    foreach ($outcome in $result) {
                        if ($outcome -isnot [Collections.IDictionary] -or !$outcome.state) { throw 'Destination must return outcome dictionaries with state.' }
                        if ($outcome.state -eq 'confirmed' -and !$outcome.acknowledgment) { throw 'confirmed requires acknowledgment.' }
                        $receipt.deliveries += @{ adapter = $receipt.adapter; outcome = $outcome }
                    }
                    if (!$result.Count) { throw 'Destination returned no outcome.' }
                }
            }
            Write-RunLog $log $receipt.adapter 'complete'
            Save-Receipt $receipt $path
        }
        if ($receipt.status -eq 'running') { $receipt.status = 'completed' }
    } catch {
        $receipt.status = 'error'
        throw
    } finally {
        try {
            $receipt.finishedAt = (Get-Date).ToString('o')
            Save-Receipt $receipt $path
            Write-RunLog $log $receipt.adapter $receipt.status
        } finally { Pop-Location }
    }
    [pscustomobject]$receipt
}

Export-ModuleMember -Function Invoke-DataAgent, Get-DataAgentReceipt
