param($Data, [hashtable] $Options)
$csv = @{} + $Options
$path = $csv.Path; $csv.Remove('Path')
$encoding = if ($csv.Encoding) { $csv.Encoding } else { 'utf8NoBOM' }; $csv.Remove('Encoding')
$strip = $csv.StripQuotes; $csv.Remove('StripQuotes')
$columns = if ($Data[0] -is [Data.DataRow]) { $Data[0].Table.Columns.ColumnName } else { $Data[0].PSObject.Properties.Name }
$lines = $Data | Select-Object $columns | ConvertTo-Csv @csv
if ($strip) { $lines = $lines | ForEach-Object { $_.Replace('"', '') } }
$lines | Set-Content -LiteralPath $path -Encoding $encoding
Get-Item -LiteralPath $path
