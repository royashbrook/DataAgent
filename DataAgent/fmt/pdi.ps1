param($Data, [hashtable] $Options)
. "$PSScriptRoot/invoice/template.ps1"
$Options = Get-InvoiceOptions $Options pdi
$rows = @(Get-InvoiceRows $Data)
& {
    foreach ($head in ($rows | Select-Object -Property $Options.Head -Unique)) {
        Expand-InvoiceLine $Options.H $head $Options.Values
        foreach ($row in ($rows | Where-Object -Property $Options.Key -EQ -Value $head.($Options.Key))) {
            if ($row.($Options.Type) -eq 'd') { Expand-InvoiceLine $Options.D $row $Options.Values }
            elseif ($row.($Options.Type) -eq 'i' -and $Options.I) { Expand-InvoiceLine $Options.I $row $Options.Values }
        }
    }
} | Set-Content -LiteralPath $Options.Path -Encoding utf8NoBOM
