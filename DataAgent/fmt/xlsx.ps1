param($Data, [hashtable] $Options)
Import-Module ImportExcel -ErrorAction Stop
$columns = if ($Data[0] -is [Data.DataRow]) { $Data[0].Table.Columns.ColumnName } else { $Data[0].PSObject.Properties.Name }
$null = $Data | Select-Object $columns | Export-Excel @Options
Get-Item -LiteralPath $Options.Path
