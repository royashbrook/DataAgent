@{
    RootModule = 'DataAgent.Sftp.psm1'
    ModuleVersion = '0.4.0'
    GUID = '4287122d-73ee-4374-bfdf-b815c5aebab7'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Sftp adapter for DataAgent.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Send-DataAgentSftp')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @(@{ ModuleName = 'Posh-SSH'; RequiredVersion = '3.2.7' })
    FileList = @('DataAgent.Sftp.psd1', 'DataAgent.Sftp.psm1', 'LICENSE')
    PrivateData = @{ PSData = @{ Tags = @('ETL', 'DataAgent'); ProjectUri = 'https://github.com/royashbrook/DataAgent'; LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE' } }
}
