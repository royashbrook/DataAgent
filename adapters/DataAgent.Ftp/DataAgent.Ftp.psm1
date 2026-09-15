function Send-DataAgentFtp {
    [CmdletBinding(SupportsShouldProcess)]
    param([IO.FileInfo[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess($Options.host, $MyInvocation.MyCommand.Name)) { return }
    if ($Options.ContainsKey('password') -or $Options.ContainsKey('pass')) { throw 'Password belongs in the environment.' }
    if (!$env:FTP_USER -or !$env:FTP_PASS) { throw 'FTP_USER and FTP_PASS required.' }
    if (!$Options.host -or !$Options.path) { throw 'FTP host and path required.' }
    if ($Options.overwrite -isnot [bool] -or !$Options.overwrite) { throw 'FTP STOR can replace an existing file; explicit overwrite: true required.' }
    if ($Options.ContainsKey('tls') -and $Options.tls -isnot [bool]) { throw 'tls must be a boolean.' }
    $tls = if ($Options.ContainsKey('tls')) { $Options.tls } else { $true }
    $port = if ($Options.port) { [int]$Options.port } else { 21 }
    foreach ($file in $Data) {
        $uri = [UriBuilder]::new('ftp', $Options.host, $port)
        $uri.Path = $Options.path.TrimEnd('/') + '/' + $file.Name
        $request = [Net.FtpWebRequest]::Create($uri.Uri)
        $request.Method = [Net.WebRequestMethods+Ftp]::UploadFile
        $request.Credentials = [Net.NetworkCredential]::new($env:FTP_USER, $env:FTP_PASS)
        $request.EnableSsl = $tls
        $request.UsePassive = $true; $request.UseBinary = $true; $request.KeepAlive = $false
        $request.Timeout = 60000; $request.ReadWriteTimeout = 60000
        $inputStream = $null; $outputStream = $null; $response = $null
        try {
            $inputStream = $file.OpenRead()
            $outputStream = $request.GetRequestStream()
            $inputStream.CopyTo($outputStream)
            $outputStream.Close()
            $response = $request.GetResponse()
            @{ state = 'submitted'; path = $file.FullName; responseCode = [int]$response.StatusCode }
        } catch { throw 'Send-DataAgentFtp failed; inspect the server privately.' }
        finally {
            if ($response) { $response.Dispose() }
            if ($outputStream) { $outputStream.Dispose() }
            if ($inputStream) { $inputStream.Dispose() }
            $request.Abort()
        }
    }
}
Export-ModuleMember -Function Send-DataAgentFtp
