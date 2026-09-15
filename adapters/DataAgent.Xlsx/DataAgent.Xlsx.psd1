@{
    RootModule = 'DataAgent.Xlsx.psm1'
    ModuleVersion = '0.4.0'
    GUID = 'e67c6a91-740f-4f3d-bedf-89e7f749eda2'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Xlsx adapter for DataAgent.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Export-DataAgentXlsx')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @(@{ ModuleName = 'ImportExcel'; RequiredVersion = '7.8.10' })
    FileList = @('DataAgent.Xlsx.psd1', 'DataAgent.Xlsx.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
