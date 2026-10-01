param($Data, [hashtable] $Options)
# a cosmos sql query over rest with the account key, one post per page: no sdk on the runner
$link = "dbs/$($Options.Database)/colls/$($Options.Container)"
$parameters = @(if ($Options.Parameters) { foreach ($p in $Options.Parameters.GetEnumerator()) { @{ name = $p.Key; value = $p.Value } } })
$body = @{ query = $Options.Query; parameters = $parameters } | ConvertTo-Json -Depth 10 -Compress
$continuation = $null
do {
    $date = [DateTime]::UtcNow.ToString('R').ToLower()
    $hmac = [Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($Options.Key))
    try { $signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("post`ndocs`n$link`n$date`n`n"))) } finally { $hmac.Dispose() }
    $headers = @{
        Authorization = [Uri]::EscapeDataString("type=master&ver=1.0&sig=$signature"); 'x-ms-date' = $date; 'x-ms-version' = '2018-12-31'
        'x-ms-documentdb-isquery' = 'true'; 'x-ms-documentdb-query-enablecrosspartition' = 'true'
    }
    if ($continuation) { $headers['x-ms-continuation'] = $continuation }
    $response = Invoke-WebRequest -Method Post -Uri "$($Options.Endpoint.TrimEnd('/'))/$link/docs" -Headers $headers -Body $body -ContentType 'application/query+json'
    ($response.Content | ConvertFrom-Json).Documents
    $continuation = "$($response.Headers['x-ms-continuation'])"
} while ($continuation)
