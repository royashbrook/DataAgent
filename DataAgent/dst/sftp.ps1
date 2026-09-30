param($Data, [hashtable] $Options)
Import-Module Posh-SSH -RequiredVersion 4.0.0 -ErrorAction Stop
$connect = $Options.connect; $send = $Options.send
$session = New-SFTPSession @connect
try {
    foreach ($file in $Data) { Set-SFTPItem -SFTPSession $session -Path $file @send }
} finally { $null = Remove-SFTPSession -SFTPSession $session }
