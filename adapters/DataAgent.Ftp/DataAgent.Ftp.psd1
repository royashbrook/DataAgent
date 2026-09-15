@{
    RootModule = 'DataAgent.Ftp.psm1'
    ModuleVersion = '0.4.0'
    GUID = '5c00ffc9-c9f3-4a2d-a297-11cc4651d104'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Ftp adapter for DataAgent.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Send-DataAgentFtp')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FileList = @('DataAgent.Ftp.psd1', 'DataAgent.Ftp.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
