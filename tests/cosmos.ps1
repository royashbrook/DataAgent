# The cosmos source over a stubbed Invoke-WebRequest: two pages, the auth header, the query body, a refusal.
$global:cosmosCalls = [Collections.Generic.List[object]]::new()
$global:cosmosKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('synthetic-key-for-the-test-only!'))
function global:Invoke-WebRequest {
    param($Method, $Uri, $Headers, $Body, $ContentType)
    $global:cosmosCalls.Add(@{ Method = $Method; Uri = $Uri; Headers = $Headers; Body = $Body; ContentType = $ContentType })
    if ($Headers['x-ms-date'] -eq 'refuse') { throw 'Unauthorized' }
    if ($Uri -match 'refusing') { throw 'Unauthorized' }
    $page = if ($Headers.ContainsKey('x-ms-continuation')) { 2 } else { 1 }
    $documents = @(@{ id = "$page-a"; billto = 'SYN'; gross = $page * 10; at = '2026-09-30T04:13:00Z' }, @{ id = "$page-b"; billto = 'SYN'; gross = $page * 10 + 1 })
    $out = [pscustomobject]@{ Content = (@{ Documents = $documents; _count = 2 } | ConvertTo-Json -Depth 5 -Compress); Headers = @{} }
    if ($page -eq 1) { $out.Headers['x-ms-continuation'] = @('token-page-2') }
    $out
}
try {
    $cfg = Config 'cosmos'
    $cfg.src = @{ adapter = 'cosmos'; args = @{ Endpoint = 'https://synthetic.documents.invalid/'; Key = $global:cosmosKey; Database = 'bc'; Container = 'orders'
        Query = 'select c.id, c.billto, c.gross from c where c.billto = @billto'; Parameters = @{ '@billto' = 'SYN' } } }
    $null = Run 'cosmos' $cfg
    $rows = @(Import-Csv "$root/cosmos/output.csv")
    Assert ($rows.Count -eq 4 -and $rows[0].id -eq '1-a' -and $rows[3].gross -eq '21') 'cosmos: both pages become rows, in order'
    Assert ($rows[0].at -ceq '2026-09-30T04:13:00Z') 'cosmos: an iso date comes through as the stored string'
    Assert ($global:cosmosCalls.Count -eq 2 -and $global:cosmosCalls[1].Headers['x-ms-continuation'] -eq 'token-page-2') 'cosmos: the second post carries the continuation token'
    $first = $global:cosmosCalls[0]
    Assert ($first.Uri -eq 'https://synthetic.documents.invalid/dbs/bc/colls/orders/docs' -and $first.ContentType -eq 'application/query+json') 'cosmos: query posts to the container docs link'
    $sent = $first.Body | ConvertFrom-Json
    Assert ($sent.query -like 'select c.id*' -and $sent.parameters[0].name -eq '@billto' -and $sent.parameters[0].value -eq 'SYN') 'cosmos: query and parameters in the body'
    $date = $first.Headers['x-ms-date']
    $hmac = [Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($global:cosmosKey))
    $expected = [Uri]::EscapeDataString("type=master&ver=1.0&sig=" + [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("post`ndocs`ndbs/bc/colls/orders`n$date`n`n"))))
    $hmac.Dispose()
    Assert ($first.Headers['Authorization'] -eq $expected -and $date -ceq $date.ToLower()) 'cosmos: master key signature over verb, resource, link and the lowercase date'
    $cfg.src.args.Endpoint = 'https://refusing.documents.invalid'
    Refuses { Run 'cosmos' $cfg } 'Unauthorized'
} finally { Remove-Item function:global:Invoke-WebRequest, variable:global:cosmosCalls, variable:global:cosmosKey }
