param($Data, [hashtable] $Options)
Import-Module SqlServer -ErrorAction Stop
Invoke-Sqlcmd @Options
