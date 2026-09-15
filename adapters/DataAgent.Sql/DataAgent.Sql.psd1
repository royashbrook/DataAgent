@{
    RootModule = 'DataAgent.Sql.psm1'
    ModuleVersion = '0.4.0'
    GUID = '093607e5-477f-4b02-b805-1b51d13770c9'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'DataAgent.Sql: adapters for the DataAgent feed runner.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Invoke-DataAgentSql')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @(@{ ModuleName = 'SqlServer'; RequiredVersion = '22.4.5.1' })
    FileList = @('DataAgent.Sql.psd1', 'DataAgent.Sql.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
