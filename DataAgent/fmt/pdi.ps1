param($Data, [hashtable] $Options)
. "$PSScriptRoot/invoice/template.ps1"
$Options = Get-InvoiceOptions $Options pdi
$rows = @(Get-InvoiceRows $Data)
& {
    foreach ($head in ($rows | Select-Object -Property $Options.Head -Unique | Sort-Object $Options.Key)) {
        Expand-InvoiceLine $Options.H $head $Options.Values
        $lines = @($rows | Where-Object -Property $Options.Key -EQ -Value $head.($Options.Key))
        foreach ($row in ($lines | Where-Object -Property $Options.Type -EQ -Value 'd')) { Expand-InvoiceLine $Options.D $row $Options.Values }
        if ($Options.I) {
            foreach ($row in ($lines | Where-Object -Property $Options.Type -EQ -Value 'i')) { Expand-InvoiceLine $Options.I $row $Options.Values }
        }
    }
} | Set-Content -LiteralPath $Options.Path -Encoding utf8NoBOM
