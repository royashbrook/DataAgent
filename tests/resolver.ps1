$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/../DataAgent/DataAgent.psd1" -Force
# PowerShell's GetType() hides PSObject wrappers; a compiled cmdlet sees the actual array elements.
Add-Type @'
using System;
public static class DataAgentElementProbe {
    public static string TypeAt(object[] values, int i) {
        return values[i] == null ? "null" : values[i].GetType().FullName;
    }
}
'@
$module = Get-Module DataAgent
function Resolve($value){ & $module { param($v) Resolve-Setting $v } $value }
function Check($value, $types){
    $resolved = Resolve @{items=$value}
    if($resolved.items.Count -ne $types.Count){ throw 'Resolved collection changed count' }
    for($i=0;$i -lt $types.Count;$i++){
        if([DataAgentElementProbe]::TypeAt($resolved.items,$i) -ne $types[$i]){ throw "CLR element type changed at $i" }
    }
}
Check @('Name=TEST','Since=none') @('System.String','System.String')
Check @() @()
Check @('one') @('System.String')
Check @('text',7,$false,$null) @('System.String','System.Int32','System.Boolean','null')
Check ([Collections.Generic.List[object]]@('first','second')) @('System.String','System.String')
$nested = Resolve @{items=@(@('nested','pair'), @{key='value'})}
if($nested.items.Count -ne 2 -or $nested.items[0].Count -ne 2 -or $nested.items[1].key -ne 'value'){ throw 'Nested collection shape changed' }
if([DataAgentElementProbe]::TypeAt($nested.items[0],0) -ne 'System.String'){ throw 'Nested string was wrapped' }
$env:DATAAGENT_RESOLVER_TEST='synthetic'
try{
    $resolved=Resolve @{items=@('env:DATAAGENT_RESOLVER_TEST'); login=@{username='test';password='env:DATAAGENT_RESOLVER_TEST'}}
    if([DataAgentElementProbe]::TypeAt($resolved.items,0) -ne 'System.String' -or $resolved.items[0] -ne 'synthetic'){ throw 'Env array resolution failed' }
    if($resolved.login -isnot [pscredential]){ throw 'Credential resolution changed' }
}finally{ Remove-Item Env:DATAAGENT_RESOLVER_TEST }
'PASS: resolver CLR strings, mixed values, empty/single/list/nested shape, env and credential checks'
