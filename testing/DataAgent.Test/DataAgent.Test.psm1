function Read-DataAgentFixture {
    [CmdletBinding()]
    param($Data, [hashtable] $Options, [hashtable] $Context)
    if ($Options.empty) { return }
    $path = if ($Options.path) { $Options.path } else { Join-Path $PSScriptRoot 'synthetic.csv' }
    Import-Csv -LiteralPath $path
}

function Write-DataAgentTestReceipt {
    [CmdletBinding(SupportsShouldProcess)]
    param([IO.FileInfo[]] $Data, [hashtable] $Options, [hashtable] $Context)
    if (!$PSCmdlet.ShouldProcess('test output', $MyInvocation.MyCommand.Name)) { return }
    if ($Options.fail) { throw 'synthetic destination failure' }
    foreach ($file in $Data) { @{ state = 'recorded'; path = $file.FullName; sha256 = (Get-FileHash -LiteralPath $file.FullName).Hash } }
}

function Test-DataAgent {
    [CmdletBinding()]
    param([string] $FixturePath)
    $root = [IO.Directory]::CreateTempSubdirectory('dataagent-test-').FullName
    $output = New-Item -ItemType Directory "$root/output"
    $cfg = @{
        keepdays = 10; purgefiles = '*.csv,*.log'
        source = @{ module = 'DataAgent.Test'; version = '0.4.0'; command = 'Read-DataAgentFixture'; options = @{ path = $FixturePath } }
        transform = @{ module = 'DataAgent.Csv'; version = '0.4.0'; command = 'Export-DataAgentCsv'; options = @{ file_format = 'test.csv' } }
        destination = @{ module = 'DataAgent.Test'; version = '0.4.0'; command = 'Write-DataAgentTestReceipt' }
    }
    $cfg | ConvertTo-Json -Depth 8 | Set-Content "$root/settings.json"
    Invoke-DataAgent -SettingsPath "$root/settings.json" -WorkingDirectory $output.FullName
}
Export-ModuleMember -Function Read-DataAgentFixture, Write-DataAgentTestReceipt, Test-DataAgent
