function Export-DataAgentXlsx {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    $name = $Options.file_format -f $Context.runAt
    if (!$name -or $name -match '[/\\]' -or [IO.Path]::GetExtension($name) -ne '.xlsx') { throw 'Invalid XLSX filename.' }
    $path = Join-Path $Context.directory $name
    if (!$PSCmdlet.ShouldProcess($path, $MyInvocation.MyCommand.Name)) { return }
    if ($Options.ContainsKey('overwrite') -and $Options.overwrite -isnot [bool]) { throw 'overwrite must be a boolean.' }
    if (!$Options.overwrite -and (Test-Path -LiteralPath $path)) { throw 'Output exists.' }
    $excel = if ($Options.excel) { $Options.excel.Clone() } else { @{} }
    foreach ($key in @('Path', 'ExcelPackage', 'InputObject', 'PassThru', 'Show', 'KillExcel', 'Append', 'NoClobber')) {
        if ($excel.ContainsKey($key)) { throw "XLSX option reserved: $key" }
    }
    $columns = if ($Data[0] -is [Data.DataRow]) { @($Data[0].Table.Columns.ColumnName) } else { @($Data[0].PSObject.Properties.Name) }
    # ImportExcel creates the workbook; use an owned directory so no existing workbook is opened.
    $stage = New-Item -ItemType Directory (Join-Path $Context.directory ([guid]::NewGuid().ToString('N')))
    $temp = Join-Path $stage.FullName 'output.xlsx'
    try {
        $null = $Data | Select-Object $columns | Export-Excel -Path $temp @excel
        [IO.File]::Move($temp, $path, [bool]$Options.overwrite)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
        Remove-Item -LiteralPath $stage.FullName
    }
    Get-Item -LiteralPath $path
}
Export-ModuleMember -Function Export-DataAgentXlsx
