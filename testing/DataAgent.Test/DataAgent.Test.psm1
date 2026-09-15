function Test-DataAgent {
    [CmdletBinding()]
    param([string] $FixturePath = "$PSScriptRoot/synthetic.csv")
    $directory = [IO.Directory]::CreateTempSubdirectory('dataagent-test-').FullName
    $cfg = @{
        src = @{ adapter = 'csv'; args = @{ LiteralPath = (Resolve-Path -LiteralPath $FixturePath).ProviderPath } }
        fmt = @{ adapter = 'csv'; args = @{ Path = 'output.csv' } }
    }
    Invoke-DataAgent -Config $cfg -WorkingDirectory $directory
    Get-Item "$directory/output.csv"
}
Export-ModuleMember -Function Test-DataAgent
