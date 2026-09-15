@{
    RootModule = 'DataAgent.Custom.psm1'
    ModuleVersion = '0.4.0'
    GUID = '33f8ce9d-d661-4ddd-9edf-a0d2a2088c69'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Custom adapter for DataAgent.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Export-DataAgentCustom')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FileList = @('DataAgent.Custom.psd1', 'DataAgent.Custom.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
