@{
    RootModule = 'DataAgent.psm1'
    ModuleVersion = '0.4.0'
    GUID = '32662c0b-0a5d-49ac-8c62-8f7ae05f79c0'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Extract, format, and deliver a file with a recorded run outcome.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Invoke-DataAgent', 'Get-DataAgentReceipt')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FileList = @('DataAgent.psd1', 'DataAgent.psm1', 'LICENSE')
    PrivateData = @{
        PSData = @{
            Tags = @('ETL', 'Data', 'CSV', 'Automation', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE'
            ProjectUri = 'https://github.com/royashbrook/DataAgent'
            ReleaseNotes = 'Review candidate: independent adapters and separate test support. Breaking config/API change from 0.3.0.'
        }
    }
}
