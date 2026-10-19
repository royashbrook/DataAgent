# Text framing is after the formatter and before delivery, so adapters keep their normal write contract.
. "$PSScriptRoot/../invoice/template.ps1"
function Add-FormatFrame($Format, $Data, $Options) {
    $scope = if ($Options.ContainsKey('Values')) { @{} + $Options['Values'] } else { @{} }
    $scope.now = if ($scope.ContainsKey('now')) { [datetime]$scope.now } else { Get-Date }
    $scope.sum = @{}
    foreach ($key in $Format.Sum.Keys) {
        $sum = $Format.Sum[$key]
        $rows = $Data
        if ($sum.UniqueBy) { $rows = $rows | Group-Object -Property $sum.UniqueBy | ForEach-Object { $_.Group[0] } }
        $scope.sum[$key] = ($rows | ForEach-Object { $_.($sum.Property) -as [decimal] } | Measure-Object -Sum).Sum
    }
    $prefix = @(foreach ($text in $Format.Prepend) { if ($null -ne $text) { Expand-InvoiceLine $text $Data[0] $scope } })
    $suffix = @(foreach ($text in $Format.Append) { if ($null -ne $text) { Expand-InvoiceLine $text $Data[0] $scope } })
    if (!$prefix.Count -and !$suffix.Count) { return }
    $encoding = if ($Options.Encoding) { $Options.Encoding } else { 'utf8NoBOM' }
    foreach ($path in @($Options.Path)) {
        if ([IO.Path]::GetExtension($path) -in '.xlsx', '.zip') { throw 'prepend/append applies to text, not XLSX or ZIP artifacts' }
        $body = Get-Content -LiteralPath $path -Raw -Encoding $encoding
        if ($suffix.Count) {
            if ($body.Length -and !$body.EndsWith("`n") -and !$body.EndsWith("`r")) { $body += [Environment]::NewLine }
            $body += ($suffix -join [Environment]::NewLine) + [Environment]::NewLine
        }
        if ($prefix.Count) { $body = ($prefix -join [Environment]::NewLine) + [Environment]::NewLine + $body }
        Set-Content -LiteralPath $path -Value $body -Encoding $encoding -NoNewline
    }
}
