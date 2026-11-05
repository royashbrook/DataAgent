param([string[]] $Data, [hashtable] $Options)
foreach ($file in $Data) {
    $headers = if ($Options.headers) { @{} + $Options.headers } else { @{} }
    # some receivers take the file's name in a header they name themselves
    if ($Options.nameheader) { $headers[$Options.nameheader] = $file }
    $post = @{ Method = 'Post'; Uri = $Options.uri; Headers = $headers; Body = Get-Content -LiteralPath $file -Raw }
    if ($Options.contenttype) { $post.ContentType = $Options.contenttype }
    # a non-2xx answer throws here with the receiver's status, so a refused post fails the run
    $response = Invoke-RestMethod @post
    Write-Host ("Response: {0}" -f $response)
}
