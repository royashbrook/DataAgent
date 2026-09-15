function Import-DataAgentCsv {
    [CmdletBinding()]
    param($Data, [hashtable] $Options, [hashtable] $Context)
    $path = $Options.path
    if (![IO.Path]::IsPathRooted($path)) { $path = Join-Path $Context.configDirectory $path }
    $path = (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
    if ((Split-Path $path) -eq $Context.directory) { throw 'CSV input must be outside the output directory.' }
    Import-Csv -LiteralPath $path -ErrorAction Stop
}

function Export-DataAgentCsv {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    $name = $Options.file_format -f $Context.runAt
    if (!$name -or $name -match '[/\\]' -or $name -in @('.', '..', ('{0:yyyyMMdd}.log' -f $Context.runAt))) { throw 'Invalid CSV filename.' }
    $path = Join-Path $Context.directory $name
    if (!$PSCmdlet.ShouldProcess($path, $MyInvocation.MyCommand.Name)) { return }
    if (Test-Path -LiteralPath $path) { throw "Export-DataAgentCsv: output exists: $name" }
    $columns = if ($Data[0] -is [Data.DataRow]) { @($Data[0].Table.Columns.ColumnName) } else { @($Data[0].PSObject.Properties.Name) }
    $Data | Select-Object $columns | Export-Csv -LiteralPath $path -NoTypeInformation -NoClobber
    Get-Item -LiteralPath $path
}
Export-ModuleMember -Function Import-DataAgentCsv, Export-DataAgentCsv
