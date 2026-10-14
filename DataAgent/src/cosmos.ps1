#requires -Version 7.5
# 7.5 for ConvertFrom-Json -DateKind; the rest of DataAgent runs on 7.4
param($Data, [hashtable] $Options)
# a cosmos sql query over rest with the account key, one post per page: no sdk on the runner
$link = "dbs/$($Options.Database)/colls/$($Options.Container)"
function Read-Cosmos([string] $Query, [hashtable] $Parameters) {
    $list = @(if ($Parameters) { foreach ($p in $Parameters.GetEnumerator()) { @{ name = $p.Key; value = $p.Value } } })
    $body = @{ query = $Query; parameters = $list } | ConvertTo-Json -Depth 10 -Compress
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
        # a source hands back what is stored: an iso date stays its string, not a local DateTime
        ($response.Content | ConvertFrom-Json -DateKind String).Documents
        $continuation = "$($response.Headers['x-ms-continuation'])"
    } while ($continuation)
}

# Fresh: a query whose one value is when the container was last loaded, and the most hours that may be
if ($Options.Fresh) {
    $last = @(Read-Cosmos $Options.Fresh.Query)[0]
    if (-not $last) { throw "cosmos freshness: '$($Options.Fresh.Query)' returned nothing." }
    $age = [datetime]::UtcNow - [datetime]::Parse($last, [cultureinfo]::InvariantCulture, 'AdjustToUniversal,AssumeUniversal')
    "cosmos last loaded $last, $([math]::Round($age.TotalMinutes)) minutes ago" | Write-Host
    if ($age.TotalHours -gt $Options.Fresh.MaxAgeHours) { throw "cosmos last loaded $([math]::Round($age.TotalHours, 1)) hours ago, over $($Options.Fresh.MaxAgeHours)." }
}

# @day is the day the run reports (AS_OF, or yesterday), @from and @to the Days days ending with it, half open
$query = if ($Options.InputFile) { Get-Content -LiteralPath $Options.InputFile -Raw } else { $Options.Query }
$day = if ($env:AS_OF) { [datetime]::ParseExact($env:AS_OF, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) } else { (Get-Date).Date.AddDays(-1) }
$days = if ($Options.Days) { [int]$Options.Days } else { 1 }
$parameters = @{ '@day' = $day.ToString('yyyy-MM-dd'); '@from' = $day.AddDays(1 - $days).ToString('yyyy-MM-dd'); '@to' = $day.AddDays(1).ToString('yyyy-MM-dd') }
$used = @{}; foreach ($k in $parameters.Keys) { if ($query -match "$k\b") { $used[$k] = $parameters[$k] } }
if ($Options.Parameters) { foreach ($p in $Options.Parameters.GetEnumerator()) { $used[$p.Key] = $p.Value } }
$documents = @(Read-Cosmos $query $used)
"cosmos for $($parameters['@day']): $($documents.Count) records" | Write-Host
if (-not $documents.Count) { return }

# a value cosmos leaves out comes back as no property at all, so every record gets every column, empty when missing
$columns = [Collections.Generic.List[string]]::new()
foreach ($d in $documents) { foreach ($p in $d.PSObject.Properties) { if (-not $columns.Contains($p.Name)) { $columns.Add($p.Name) } } }
$en = [cultureinfo]::InvariantCulture
$rows = foreach ($d in $documents) {
    $row = [ordered]@{}
    foreach ($c in $columns) {
        $v = $d.$c
        if ($null -eq $v) { $v = '' }
        # Formats: a column of stored iso dates written in a .net date format
        elseif ($Options.Formats -and $Options.Formats.Contains($c) -and "$v") { $v = [datetime]::Parse($v, $en).ToString($Options.Formats[$c], $en) }
        # Map: a column's codes to the names a customer knows, matched trimmed, the stored value when the code has none
        elseif ($Options.Map -and $Options.Map.Contains($c) -and $Options.Map[$c]["$v".Trim()]) { $v = $Options.Map[$c]["$v".Trim()] }
        $row[$c] = $v
    }
    [pscustomobject]$row
}
# Sort: columns to order by, in order; Drop: columns that were only there to sort on
if ($Options.Sort) { $rows = $rows | Sort-Object -Property @($Options.Sort) -Stable }
if ($Options.Drop) { $rows = $rows | Select-Object -Property * -ExcludeProperty @($Options.Drop) }
$rows
