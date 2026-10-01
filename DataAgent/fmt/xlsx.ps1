param($Data, [hashtable] $Options)
Import-Module ImportExcel -RequiredVersion 7.8.10 -ErrorAction Stop
$columns = if ($Data[0] -is [Data.DataRow]) { $Data[0].Table.Columns.ColumnName } else { $Data[0].PSObject.Properties.Name }
# Export-Excel writes into a workbook that is already there, so a shorter run would leave the last run's rows below its own
if (Test-Path -LiteralPath $Options.Path) { Remove-Item -LiteralPath $Options.Path }
$null = $Data | Select-Object $columns | Export-Excel @Options
