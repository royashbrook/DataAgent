param($Data, [hashtable] $Options)
foreach ($file in $Data) {
    $request = [Net.FtpWebRequest]::Create($Options.Uri.TrimEnd('/') + '/' + [Uri]::EscapeDataString([IO.Path]::GetFileName($file)))
    $request.Method = [Net.WebRequestMethods+Ftp]::UploadFile
    $request.EnableSsl = $true
    $request.Credentials = if ($Options.Credential -is [pscredential]) { $Options.Credential.GetNetworkCredential() } else { $Options.Credential }
    $inputStream = $null; $outputStream = $null; $response = $null
    try {
        $inputStream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $file).ProviderPath)
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
