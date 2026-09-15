param($Data, [hashtable] $Options)
Import-Module Posh-SSH -ErrorAction Stop
$connect = $Options.connect; $send = $Options.send
$session = New-SFTPSession @connect
try {
    foreach ($file in $Data) { Set-SFTPItem -SFTPSession $session -Path $file.FullName @send }
} finally { $null = Remove-SFTPSession -SFTPSession $session }
