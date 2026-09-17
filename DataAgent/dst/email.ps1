param([string[]] $Data, [hashtable] $Options)
if ($Data.Count -ne 1) { throw 'email requires one file; multiple attachments are not supported' }
Import-Module Send-FileViaEmail -ErrorAction Stop
Send-FileViaEmail -file $Data[0] @Options
