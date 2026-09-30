param($Data, [hashtable] $Options)
Import-Module SqlServer -RequiredVersion 22.4.5.1 -ErrorAction Stop
Invoke-Sqlcmd @Options | ForEach-Object { if ($_ -is [Data.DataTable]) { $_.Rows } else { $_ } }
