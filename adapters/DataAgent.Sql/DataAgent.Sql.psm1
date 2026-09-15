function Invoke-DataAgentSql {
    [CmdletBinding(SupportsShouldProcess)]
    param($Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess('SQL', $MyInvocation.MyCommand.Name)) { return }
    if ($Options.ContainsKey('ConnectionString')) { throw 'ConnectionString belongs in the environment.' }
    if (!$env:CONNECTION_STRING) { throw 'CONNECTION_STRING required.' }
    $sql = $Options.Clone()
    if ($sql.InputFile -and ![IO.Path]::IsPathRooted($sql.InputFile)) { $sql.InputFile = Join-Path $Context.configDirectory $sql.InputFile }
    $sql.ConnectionString = $env:CONNECTION_STRING
    try { Invoke-Sqlcmd @sql -ErrorAction Stop }
    catch { throw 'Invoke-DataAgentSql failed; inspect the provider privately.' }
}
Export-ModuleMember -Function Invoke-DataAgentSql
