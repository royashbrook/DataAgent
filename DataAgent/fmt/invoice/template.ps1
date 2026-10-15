# Shared substitution for the three invoice layouts. No expression evaluation: config supplies
# values and .NET format strings, not PowerShell. Alignment is minimum width, never truncation.
function Get-InvoiceOptions($Overrides, $Name) {
    $options = Import-PowerShellDataFile "$PSScriptRoot/$Name.psd1"
    foreach ($key in $Overrides.Keys) { $options[$key] = $Overrides[$key] }
    $options
}

function Get-InvoiceRows($Rows) {
    if ($Rows[0] -is [Data.DataRow]) { $Rows | Select-Object $Rows[0].Table.Columns.ColumnName }
    else { $Rows }
}

function Expand-InvoiceLine([string] $Template, $Row, [hashtable] $Scope = @{}) {
    $out = [Text.StringBuilder]::new()
    $at = 0
    foreach ($m in [regex]::Matches($Template, '\{([\w.]+)(,-?\d+)?(?::([^}]+))?\}')) {
        $null = $out.Append($Template, $at, $m.Index - $at)
        $parts = $m.Groups[1].Value.Split('.')
        $value = if ($Scope.ContainsKey($parts[0])) { $Scope[$parts[0]] } else { $Row.($parts[0]) }
        foreach ($part in @($parts | Select-Object -Skip 1)) { $value = $value.$part }
        $format = '{0' + $m.Groups[2].Value
        if ($m.Groups[3].Success) { $format += ':' + $m.Groups[3].Value }
        else { $value = "$value" }
        $null = $out.Append(($format + '}') -f $value)
        $at = $m.Index + $m.Length
    }
    $null = $out.Append($Template, $at, $Template.Length - $at)
    $out.ToString()
}
