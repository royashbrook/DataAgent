function Send-DataAgentSftp {
    [CmdletBinding(SupportsShouldProcess)]
    param([IO.FileInfo[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess($Options.host, $MyInvocation.MyCommand.Name)) { return }
    if ($Options.ContainsKey('password') -or $Options.ContainsKey('pass')) { throw 'Password belongs in the environment.' }
    if (!$env:FTP_USER -or !$env:FTP_PASS) { throw 'FTP_USER and FTP_PASS required.' }
    if (!$Options.host -or !$Options.path) { throw 'SFTP host and path required.' }
    if ($Options.ContainsKey('overwrite') -and $Options.overwrite -isnot [bool]) { throw 'overwrite must be a boolean.' }
    $port = if ($Options.port) { [int]$Options.port } else { 22 }
    $credential = [pscredential]::new($env:FTP_USER, (ConvertTo-SecureString $env:FTP_PASS -AsPlainText -Force))
    $session = $null
    try {
        $session = New-SFTPSession -ComputerName $Options.host -Port $port -Credential $credential -ErrorOnUntrusted -ConnectionTimeout 30 -OperationTimeout 60
        foreach ($file in $Data) {
            $null = Set-SFTPItem -SFTPSession $session -Destination $Options.path -Path $file.FullName -Force:([bool]$Options.overwrite)
            @{ state = 'submitted'; path = $file.FullName; destination = $Options.path }
        }
    } catch { throw 'Send-DataAgentSftp failed; inspect the server privately.' }
    finally { if ($session) { $null = Remove-SFTPSession -SFTPSession $session } }
}
Export-ModuleMember -Function Send-DataAgentSftp
