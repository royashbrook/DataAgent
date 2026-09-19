param([string] $ModulePath = "$PSScriptRoot/../DataAgent")
$ErrorActionPreference = 'Stop'
$ModulePath = (Resolve-Path $ModulePath).Path
$brief = Get-Content "$ModulePath/CAPABILITIES.md" -Raw
$documented = @{}
foreach ($line in $brief -split '\r?\n') {
    if ($line -notmatch '^\| `(src|fmt|dst)/([^`]+)` \| (.+) \| (.+) \|$') { continue }
    $name = "$($Matches[1])/$($Matches[2])"
    if ($documented.ContainsKey($name)) { throw "duplicate adapter: $name" }
    $documented[$name] = @{
        owned = @([regex]::Matches($Matches[3], '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
        helpers = @([regex]::Matches($Matches[4], '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
    }
}
$files = @(Get-ChildItem "$ModulePath/src/*.ps1", "$ModulePath/fmt/*.ps1", "$ModulePath/dst/*.ps1")
$names = @($files | ForEach-Object { "$($_.Directory.Name)/$($_.BaseName)" })
if (Compare-Object @($documented.Keys | Sort-Object) @($names | Sort-Object)) { throw 'adapter inventory differs from brief' }
foreach ($file in $files) {
    $name = "$($file.Directory.Name)/$($file.BaseName)"
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { throw $errors[0] }
    # Direct properties on Options (and csv's copy), not helper-owned splatted parameters.
    $reads = $ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.MemberExpressionAst] -and
        $node -isnot [Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Expression -is [Management.Automation.Language.VariableExpressionAst] -and
        $node.Expression.VariablePath.UserPath -in @('Options', 'csv')
    }, $true)
    $owned = @($reads | ForEach-Object { $_.Member.Value } | Sort-Object -Unique)
    if (Compare-Object $owned @($documented[$name].owned | Sort-Object)) { throw "owned options differ: $name" }
    foreach ($helper in $documented[$name].helpers) {
        if (!$ast.Extent.Text.Contains($helper)) { throw "helper absent from adapter: $name / $helper" }
    }
}
$manifest = Import-PowerShellDataFile "$ModulePath/DataAgent.psd1"
if ('CAPABILITIES.md' -notin $manifest.FileList) { throw 'brief missing from package FileList' }
"PASS: capability inventory and direct option reads ($($files.Count) adapters)"
