@{
    RootModule = 'DataAgent.psm1'
    ModuleVersion = '0.10.0'
    GUID = '32662c0b-0a5d-49ac-8c62-8f7ae05f79c0'
    Author = 'Roy Ashbrook'
    Copyright = '(c) 2026 Roy Ashbrook. MIT License.'
    Description = 'Run a configured source, formatter, and destination using existing PowerShell tools.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Invoke-DataAgent')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    FileList = @('DataAgent.psd1', 'DataAgent.psm1', 'LICENSE', 'CAPABILITIES.md', 'src/sql.ps1', 'src/csv.ps1', 'src/cosmos.ps1', 'fmt/csv.ps1', 'fmt/xlsx.ps1', 'fmt/custom.ps1', 'fmt/pdi.ps1', 'fmt/x12-210.ps1', 'fmt/dtn.ps1', 'fmt/invoice/template.ps1', 'fmt/invoice/pdi.psd1', 'fmt/invoice/x12-210.psd1', 'fmt/invoice/dtn.psd1', 'fmt/text/frame.ps1', 'dst/email.ps1', 'dst/sftp.ps1', 'dst/ftp.ps1', 'dst/ftps.ps1')
    PrivateData = @{
        PSData = @{
            Tags = @('ETL', 'Data', 'CSV', 'Automation', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri = 'https://github.com/royashbrook/DataAgent/blob/main/LICENSE'
            ProjectUri = 'https://github.com/royashbrook/DataAgent'
            ReleaseNotes = 'Preserve invoice input order. Add configured x12 conditions, control/date schemes, separators, terminators and legacy counts. Add text prepend/append with optional distinct-key sums, and per-invoice footer templates. No helper pin or destination changes. Re-prove receiver output before adoption.'
        }
    }
}
