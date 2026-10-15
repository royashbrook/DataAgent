param($Data, [hashtable] $Options)
. "$PSScriptRoot/invoice/template.ps1"
$Options = Get-InvoiceOptions $Options dtn
$scope = @{} + $Options.Values
& {
    foreach ($t in $Options.Head) { Expand-InvoiceLine $t $null $scope }
    $scope.n = [int]$Options.Start
    foreach ($invoice in $Data) {
        foreach ($t in $Options.Open) { Expand-InvoiceLine $t $invoice $scope }
        '"{0}"' -f (@(foreach ($f in $Options.Header) { Expand-InvoiceLine $f $invoice $scope }) -join '","')
        $scope.invoice = $invoice
        foreach ($detail in $invoice.($Options.Detail)) {
            '"{0}"' -f (@(foreach ($f in $Options.Line) { Expand-InvoiceLine $f $detail $scope }) -join '","')
        }
        $scope.Remove('invoice')
        foreach ($t in $Options.Close) { Expand-InvoiceLine $t $invoice $scope }
        $scope.n++
    }
    foreach ($t in $Options.Tail) { Expand-InvoiceLine $t $null $scope }
} | Set-Content -LiteralPath $Options.Path -Encoding utf8NoBOM
