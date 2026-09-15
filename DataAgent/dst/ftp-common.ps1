param($Data, [hashtable] $Options, [bool] $Tls)
foreach ($file in $Data) {
    $request = [Net.FtpWebRequest]::Create($Options.Uri.TrimEnd('/') + '/' + [Uri]::EscapeDataString($file.Name))
    $request.Method = [Net.WebRequestMethods+Ftp]::UploadFile
    $request.EnableSsl = $Tls
    $request.Credentials = if ($Options.Credential -is [pscredential]) { $Options.Credential.GetNetworkCredential() } else { $Options.Credential }
    $inputStream = $null; $outputStream = $null; $response = $null
    try {
        $inputStream = $file.OpenRead()
        $outputStream = $request.GetRequestStream()
        $inputStream.CopyTo($outputStream)
        $outputStream.Close()
        $response = $request.GetResponse()
    } finally {
        if ($response) { $response.Dispose() }
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        $request.Abort()
    }
}
