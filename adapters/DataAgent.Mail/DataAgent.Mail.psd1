@{
    RootModule = 'DataAgent.Mail.psm1'
    ModuleVersion = '0.4.0'
    GUID = '96110483-3e59-4e05-9a5d-cf28b65fbdf3'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'DataAgent.Mail: adapters for the DataAgent feed runner.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Send-DataAgentMail')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @(@{ ModuleName = 'Send-FileViaEmail'; RequiredVersion = '2.0.0.0' })
    FileList = @('DataAgent.Mail.psd1', 'DataAgent.Mail.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
