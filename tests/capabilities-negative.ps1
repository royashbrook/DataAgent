$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('dataagent-brief-' + [guid]::NewGuid())
Copy-Item "$PSScriptRoot/../DataAgent" $root -Recurse
$brief = Get-Content "$root/CAPABILITIES.md" -Raw
Set-Content "$root/CAPABILITIES.md" ($brief -replace '\r?\n', "`r`n") -NoNewline
& "$PSScriptRoot/capabilities.ps1" -ModulePath $root
function Refuses($message) {
    try { & "$PSScriptRoot/capabilities.ps1" -ModulePath $root }
    catch { if ($_.Exception.Message -like "*$message*") { return }; throw }
    throw "did not refuse: $message"
}
'param($Data,$Options)' | Set-Content "$root/src/unlisted.ps1"
Refuses 'adapter inventory differs'
Remove-Item "$root/src/unlisted.ps1"
$csv = Get-Content "$root/fmt/csv.ps1" -Raw
'$null = $Options.NewOption' | Add-Content "$root/fmt/csv.ps1"
Refuses 'owned options differ'
Set-Content "$root/fmt/csv.ps1" $csv
$manifest = Get-Content "$root/DataAgent.psd1" -Raw
$manifest.Replace("'CAPABILITIES.md', ", '') | Set-Content "$root/DataAgent.psd1"
Refuses 'brief missing from package FileList'
"PASS: accepts CRLF; rejects undocumented adapter, undocumented option and unpackaged brief"
