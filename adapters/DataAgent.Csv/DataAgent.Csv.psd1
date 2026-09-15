@{
    RootModule = 'DataAgent.Csv.psm1'
    ModuleVersion = '0.4.0'
    GUID = 'c527ef34-3d92-4351-9480-7d36bb42cf1c'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'DataAgent.Csv: adapters for the DataAgent feed runner.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Import-DataAgentCsv', 'Export-DataAgentCsv')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @()
    FileList = @('DataAgent.Csv.psd1', 'DataAgent.Csv.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
