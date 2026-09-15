@{
    RootModule = 'DataAgent.psm1'
    ModuleVersion = '0.3.0'
    GUID = '32662c0b-0a5d-49ac-8c62-8f7ae05f79c0'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Extract, format, and deliver a file with a recorded run outcome.'
    PowerShellVersion = '7.4'
    RequiredModules = @(
        @{ ModuleName = 'Add-PrefixForLogging'; RequiredVersion = '1.0.0.2' }
        @{ ModuleName = 'Clear-Files'; RequiredVersion = '1.0.0.0' }
    )
    FunctionsToExport = @('Invoke-DataAgent', 'Get-DataAgentReceipt', 'Invoke-DataAgentPipeline', 'Invoke-DataAgentSql', 'Export-DataAgentCsv', 'Send-DataAgentMail', 'Write-DataAgentRecording')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FileList = @('DataAgent.psd1', 'DataAgent.psm1', 'synthetic.csv', 'LICENSE')
    PrivateData = @{
        PSData = @{
            Tags = @('ETL', 'Data', 'CSV', 'Automation', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE'
            ProjectUri = 'https://github.com/royashbrook/DataAgent'
            ReleaseNotes = 'Initial public DataAgent release. Config-driven feeds, mock and dry-run modes, bounded receipts, and offline acceptance tests.'
        }
    }
}
