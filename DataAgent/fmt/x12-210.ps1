param($Data, [hashtable] $Options)
. "$PSScriptRoot/invoice/template.ps1"
$Options = Get-InvoiceOptions $Options 'x12-210'
$rows = @(Get-InvoiceRows $Data)
$now = $Options.Values.now
$scope = @{} + $Options.Values
# Kept from the extracted daily-job convention, not a unique interchange-number service.
$scope.control = [int]('{0:00}{1:0000}' -f $now.ToString('yy'), ($now - [datetime]::new($now.Year, 1, 1)).TotalHours)
$scope.day = $now.DayOfYear
if ($Options.Control) { $scope.control = Expand-InvoiceLine $Options.Control $null $scope }
if ($Options.Values.ContainsKey('control')) { $scope.control = $Options.Values.control }
$scope.dates = @{}
foreach ($key in $Options.Dates.Keys) { $scope.dates[$key] = $now.AddDays($Options.Dates[$key]) }

function Expand-X12Segments($Templates, $Row) {
    foreach ($entry in @($Templates)) {
        $text = $entry
        if ($entry -is [Collections.IDictionary]) {
            if ($entry.When) {
                $value = $Row.($entry.When.Field)
                $match = if ($entry.When.ContainsKey('Is')) { [string]$value -eq [string]$entry.When.Is }
                    else { ![string]::IsNullOrEmpty([string]$value) }
                if ($entry.When.Not) { $match = !$match }
                if (!$match) { continue }
            }
            $text = $entry.Text
        }
        foreach ($line in @($text)) {
            (Expand-InvoiceLine ($line.Replace('*', $Options.Separator)) $Row $scope) + $Options.Terminator
        }
    }
}
& {
    Expand-X12Segments $Options.Head $null
    $st = 0
    foreach ($invoice in ($rows | Select-Object -Property * -ExcludeProperty $Options.Detail -Unique)) {
        $scope.st = ++$st
        $segments = [Collections.Generic.List[string]]::new()
        foreach ($segment in (Expand-X12Segments $Options.Invoice $invoice)) { $segments.Add($segment) }
        $lx = 0
        $detailCount = 0
        foreach ($line in ($rows | Where-Object -Property $Options.Key -EQ -Value $invoice.($Options.Key))) {
            $scope.lx = ++$lx
            foreach ($segment in (Expand-X12Segments $Options.Line $line)) { $segments.Add($segment); $detailCount++ }
        }
        foreach ($segment in (Expand-X12Segments $Options.Close $invoice)) { $segments.Add($segment) }
        $scope.se = $segments.Count + 1 + [int]$Options.SeExtra
        if ($null -ne $Options.SeDetailCount) { $scope.se += [int]$Options.SeDetailCount * $lx - $detailCount }
        foreach ($segment in (Expand-X12Segments $Options.Se $invoice)) { $segments.Add($segment) }
        $segments
    }
    $scope.invoices = $st
    Expand-X12Segments $Options.Tail $null
} | Set-Content -LiteralPath $Options.Path -Encoding utf8NoBOM
