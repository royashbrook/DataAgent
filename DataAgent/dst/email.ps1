param($Data, [hashtable] $Options)
Import-Module Send-FileViaEmail -ErrorAction Stop
foreach ($file in $Data) { Send-FileViaEmail -file $file.FullName @Options }
