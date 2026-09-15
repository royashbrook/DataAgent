param($Data, [hashtable] $Options)
Import-Module Send-FileViaEmail -ErrorAction Stop
foreach ($file in $Data) {
    # The existing helper uses its file argument as the attachment name, too.
    Push-Location -LiteralPath $file.DirectoryName
    try { Send-FileViaEmail -file $file.Name @Options } finally { Pop-Location }
}
