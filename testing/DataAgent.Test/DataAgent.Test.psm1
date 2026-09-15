function Test-DataAgent {
    [CmdletBinding()]
    param([string] $FixturePath = "$PSScriptRoot/synthetic.csv")
    $directory = [IO.Directory]::CreateTempSubdirectory('dataagent-test-').FullName
    $cfg = @{
        src = @{ adapter = 'csv'; args = @{ LiteralPath = (Resolve-Path -LiteralPath $FixturePath).ProviderPath } }
        fmt = @{ adapter = 'csv'; args = @{ Path = 'output.csv' } }
    }
    'param($Config); Invoke-DataAgent $Config' | Set-Content "$directory/job.ps1"
    & "$directory/job.ps1" $cfg
    Get-Item "$directory/output.csv"
}
Export-ModuleMember -Function Test-DataAgent
