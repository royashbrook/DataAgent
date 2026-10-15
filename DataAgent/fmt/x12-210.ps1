param($Data, [hashtable] $Options)
. "$PSScriptRoot/invoice/template.ps1"
$Options = Get-InvoiceOptions $Options 'x12-210'
$rows = @(Get-InvoiceRows $Data)
$now = Get-Date
$scope = @{} + $Options.Values
$scope.now = $now
# Kept from the extracted daily-job convention, not a unique interchange-number service.
$scope.control = [int]('{0:00}{1:0000}' -f $now.ToString('yy'), ($now - [datetime]::new($now.Year, 1, 1)).TotalHours)
foreach ($key in 'now', 'control') { if ($Options.Values.ContainsKey($key)) { $scope[$key] = $Options.Values[$key] } }
& {
    foreach ($t in $Options.Head) { Expand-InvoiceLine $t $null $scope }
    $st = 0
    foreach ($invoice in ($rows | Select-Object -Property * -ExcludeProperty $Options.Detail -Unique)) {
        $scope.st = ++$st
        $segments = [Collections.Generic.List[string]]::new()
        foreach ($t in $Options.Invoice) { $segments.Add((Expand-InvoiceLine $t $invoice $scope)) }
        $lx = 0
        foreach ($line in ($rows | Where-Object -Property $Options.Key -EQ -Value $invoice.($Options.Key))) {
            $scope.lx = ++$lx
            foreach ($t in $Options.Line) { $segments.Add((Expand-InvoiceLine $t $line $scope)) }
        }
        foreach ($t in $Options.Close) { $segments.Add((Expand-InvoiceLine $t $invoice $scope)) }
        $scope.se = $segments.Count + 1 + [int]$Options.SeExtra
        $segments.Add((Expand-InvoiceLine $Options.Se $invoice $scope))
        $segments
    }
    $scope.invoices = $st
    foreach ($t in $Options.Tail) { Expand-InvoiceLine $t $null $scope }
} | Set-Content -LiteralPath $Options.Path -Encoding utf8NoBOM
