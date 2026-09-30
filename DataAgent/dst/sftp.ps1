param($Data, [hashtable] $Options)
Import-Module Posh-SSH -RequiredVersion 4.0.0 -ErrorAction Stop
$connect = $Options.connect; $send = $Options.send
$attempts = if ($Options.attempts) { [int]$Options.attempts } else { 3 }
$delay = if ($null -ne $Options.delay) { [int]$Options.delay } else { 60 }
# a partner host that does not answer for a minute is the usual sftp failure, so the connect tries again; a bad login fails the same way, just three times
for ($try = 1; $true; $try++) {
    try { $session = New-SFTPSession @connect; break }
    catch { if ($try -ge $attempts) { throw }; Write-Warning "sftp connect $try of $attempts failed: $($_.Exception.Message)"; Start-Sleep -Seconds $delay }
}
try {
    foreach ($file in $Data) { Set-SFTPItem -SFTPSession $session -Path $file @send }
} finally { $null = Remove-SFTPSession -SFTPSession $session }
