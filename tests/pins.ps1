# every helper the module imports is pinned, and the brief and the CI install list say the same versions
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$pins = @{}
foreach ($line in Get-ChildItem "$repo/DataAgent" -Recurse -Include *.ps1, *.psm1 | Select-String 'Import-Module (\S+)(.*)$') {
    $name = $line.Matches[0].Groups[1].Value; $rest = $line.Matches[0].Groups[2].Value
    # fmt/custom imports the feed's own module by path, that one is the feed's to version
    if ($name -like '(*' -or $name -like '$*') { continue }
    if ($rest -notmatch '-RequiredVersion (\d+(\.\d+){2,3})\b') { throw "unpinned helper: $($line.Filename) imports $name without -RequiredVersion" }
    if ($pins[$name] -and $pins[$name] -ne $Matches[1]) { throw "two pins for $name" }
    $pins[$name] = $Matches[1]
}
if ($pins.Count -lt 6) { throw "expected the six helpers pinned, found $($pins.Count)" }
$brief = Get-Content "$repo/DataAgent/CAPABILITIES.md" -Raw
foreach ($name in $pins.Keys) {
    if ($brief -notmatch "\b$([regex]::Escape($name)) $([regex]::Escape($pins[$name]))\b") { throw "brief does not list $name $($pins[$name])" }
}
foreach ($line in Get-Content "$repo/.github/workflows/test.yml" | Select-String 'Install-Module (\S+) -RequiredVersion (\S+)') {
    $name = $line.Matches[0].Groups[1].Value; $version = $line.Matches[0].Groups[2].Value
    if ($pins[$name] -ne $version) { throw "test.yml installs $name $version, the module pins $($pins[$name])" }
}
"PASS: $($pins.Count) helpers pinned, brief and CI agree: " + (($pins.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Value)" }) -join ', ')
