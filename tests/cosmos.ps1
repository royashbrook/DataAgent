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
} finally { Remove-Item function:global:Invoke-WebRequest, variable:global:cosmosCalls }

# The query file, the day window, freshness, and the shaping a cosmos query cannot do itself, over a stub that
# answers the freshness query with a marker and anything else with three records in no useful order.
$global:cosmosBodies = [Collections.Generic.List[object]]::new()
$global:cosmosMarker = [datetime]::UtcNow.AddHours(-1).ToString('o')
function global:Invoke-WebRequest {
    param($Method, $Uri, $Headers, $Body, $ContentType)
    $sent = $Body | ConvertFrom-Json
    $global:cosmosBodies.Add($sent)
    $documents = if ($sent.query -match '_sync') { @(@($global:cosmosMarker) | Where-Object { $_ }) } else {
        @(
            [ordered]@{ _order = 2; _line = 1; Name = 'b'; When = '2026-10-13T03:25:00'; Code = ' EXX ' }
            [ordered]@{ _order = 1; _line = 2; Name = 'a'; When = ''; Code = 'ZZZ' }
            [ordered]@{ _order = 1; _line = 1; Name = 'a2'; Code = 'EXX'; Extra = 'x' }
        )
    }
    [pscustomobject]@{ Content = (@{ Documents = $documents } | ConvertTo-Json -Depth 5 -Compress); Headers = @{} }
}
try {
    $env:AS_OF = '2026-10-13'
    $cfg = Config 'cosmos-shape'
    'select value c from c where c.billto = @billto and c.day >= @from and startswith(c.done, @day)' | Set-Content "$root/cosmos-shape/get-data.sql"
    $fresh = @{ Query = "select value c.lastSuccess from c where c.id = '_sync'"; MaxAgeHours = 24 }
    $cfg.src = @{ adapter = 'cosmos'; args = @{ Endpoint = 'https://synthetic.documents.invalid'; Key = $global:cosmosKey; Database = 'bc'; Container = 'orders'
        InputFile = 'get-data.sql'; Parameters = @{ '@billto' = 'SYN' }; Days = 3; Fresh = $fresh
        Formats = @{ When = 'MM/dd/yyyy HH:mm' }; Map = @{ Code = @{ EXX = 'Exxon' } }; Sort = @('_order', '_line'); Drop = @('_order', '_line') } }
    $null = Run 'cosmos-shape' $cfg
    $query = $global:cosmosBodies | Where-Object { $_.query -notmatch '_sync' } | Select-Object -First 1
    $values = @{}; foreach ($p in $query.parameters) { $values[$p.name] = $p.value }
    Assert ($query.query -like 'select value c from c where c.billto = @billto*') 'cosmos: InputFile is the query'
    Assert ($values['@day'] -eq '2026-10-13' -and $values['@from'] -eq '2026-10-11' -and $values['@billto'] -eq 'SYN' -and -not $values.ContainsKey('@to')) 'cosmos: @day is AS_OF, @from opens a Days window, and only the parameters the query uses are sent'
    $lines = @(Get-Content "$root/cosmos-shape/output.csv")
    Assert ($lines[0] -ceq '"Name","When","Code","Extra"') 'cosmos: every column any record has, in first-seen order, less the dropped sort columns'
    Assert ($lines[1] -ceq '"a2","","Exxon","x"' -and $lines[2] -ceq '"a","","ZZZ",""' -and $lines[3] -ceq '"b","10/13/2026 03:25","Exxon",""') 'cosmos: sorted, a missing value empty, dates formatted, codes mapped trimmed, an unmapped code kept'
    $global:cosmosMarker = [datetime]::UtcNow.AddHours(-30).ToString('o')
    Refuses { Run 'cosmos-shape' $cfg } 'over 24'
    $global:cosmosMarker = $null
    Refuses { Run 'cosmos-shape' $cfg } 'returned nothing'
} finally { Remove-Item Env:AS_OF -ErrorAction Ignore; Remove-Item function:global:Invoke-WebRequest, variable:global:cosmosBodies, variable:global:cosmosMarker }
Remove-Item variable:global:cosmosKey
