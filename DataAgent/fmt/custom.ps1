param($Data, [hashtable] $Options)
$module = Import-Module (Resolve-Path -LiteralPath $Options.Module).ProviderPath -PassThru -Force -ErrorAction Stop
if ($Data[0] -is [Data.DataRow]) {
    $table = $Data[0].Table.Clone()
    foreach ($row in $Data) { $table.ImportRow($row) }
} else {
    $table = [Data.DataTable]::new()
    foreach ($name in $Data[0].PSObject.Properties.Name) { $null = $table.Columns.Add($name, [object]) }
    foreach ($record in $Data) {
        $row = $table.NewRow()
        foreach ($column in $table.Columns) { $row[$column.ColumnName] = if ($null -eq $record.($column.ColumnName)) { [DBNull]::Value } else { $record.($column.ColumnName) } }
        $table.Rows.Add($row)
    }
}
& $module.ExportedCommands['ConvertTo-Custom'] $table | Set-Content -LiteralPath $Options.Path -Encoding utf8NoBOM
Get-Item -LiteralPath $Options.Path
