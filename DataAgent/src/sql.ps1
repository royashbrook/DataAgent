param($Data, [hashtable] $Options)
Import-Module SqlServer -ErrorAction Stop
Invoke-Sqlcmd @Options | ForEach-Object { if ($_ -is [Data.DataTable]) { $_.Rows } else { $_ } }
