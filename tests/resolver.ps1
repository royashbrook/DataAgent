$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/../DataAgent/DataAgent.psd1" -Force
# PowerShell's GetType() hides PSObject wrappers; GetTypeArray sees the actual CLR elements.
$module = Get-Module DataAgent
function Resolve($value){ & $module { param($v) Resolve-Setting $v } $value }
function Check($value, $types){
    $resolved = Resolve @{items=$value}
    if($resolved.items.Count -ne $types.Count){ throw 'Resolved collection changed count' }
    $actual = [Type]::GetTypeArray($resolved.items)
    for($i=0;$i -lt $types.Count;$i++){
        if($actual[$i].FullName -ne $types[$i]){ throw "CLR element type changed at $i" }
    }
}
Check @('Name=TEST','Since=none') @('System.String','System.String')
Check @() @()
Check @('one') @('System.String')
Check @('text',7,$false) @('System.String','System.Int32','System.Boolean')
$nulls = Resolve @{items=@($null,'kept')}
if($nulls.items.Count -ne 2 -or $null -ne $nulls.items[0] -or $nulls.items[1] -ne 'kept'){ throw 'Null slot changed' }
Check ([Collections.Generic.List[object]]@('first','second')) @('System.String','System.String')
$nested = Resolve @{items=@(@('nested','pair'), @{key='value'})}
if($nested.items.Count -ne 2 -or $nested.items[0].Count -ne 2 -or $nested.items[1].key -ne 'value'){ throw 'Nested collection shape changed' }
if([Type]::GetTypeArray($nested.items[0])[0].FullName -ne 'System.String'){ throw 'Nested string was wrapped' }
$env:DATAAGENT_RESOLVER_TEST='synthetic'
try{
    $resolved=Resolve @{items=@('env:DATAAGENT_RESOLVER_TEST'); login=@{username='test';password='env:DATAAGENT_RESOLVER_TEST'}}
    if([Type]::GetTypeArray($resolved.items)[0].FullName -ne 'System.String' -or $resolved.items[0] -ne 'synthetic'){ throw 'Env array resolution failed' }
    if($resolved.login -isnot [pscredential]){ throw 'Credential resolution changed' }
}finally{ Remove-Item Env:DATAAGENT_RESOLVER_TEST }
'PASS: resolver CLR strings, mixed values, empty/single/list/nested shape, env and credential checks'
