@{
    RootModule = 'DataAgent.Test.psm1'
    ModuleVersion = '0.4.1'
    GUID = '3d16fcb0-a991-4c65-a6e4-3bfcd360688d'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Optional synthetic CSV exercise for DataAgent.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Test-DataAgent')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @(@{ ModuleName = 'DataAgent'; RequiredVersion = '0.4.1' })
    FileList = @('DataAgent.Test.psd1', 'DataAgent.Test.psm1', 'LICENSE', 'synthetic.csv')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
