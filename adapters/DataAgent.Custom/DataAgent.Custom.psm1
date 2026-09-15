function Export-DataAgentCustom {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    $name = $Options.file_format -f $Context.runAt
    if (!$name -or $name -match '[/\\]' -or $name -in @('.', '..', ('{0:yyyyMMdd}.log' -f $Context.runAt))) { throw 'Invalid output filename.' }
    $path = Join-Path $Context.directory $name
    if (!$PSCmdlet.ShouldProcess($path, $MyInvocation.MyCommand.Name)) { return }
    if ($Options.ContainsKey('overwrite') -and $Options.overwrite -isnot [bool]) { throw 'overwrite must be a boolean.' }
    if (!$Options.overwrite -and (Test-Path -LiteralPath $path)) { throw 'Output exists.' }
    $converter = $Options.converter
    if (![IO.Path]::IsPathRooted($converter)) { $converter = Join-Path $Context.configDirectory $converter }
    $module = Import-Module (Resolve-Path -LiteralPath $converter).ProviderPath -PassThru -Force
    $command = $module.ExportedCommands['ConvertTo-Custom']
    if (!$command) { throw 'Converter must export ConvertTo-Custom.' }
    # Rebuild the selected rows, not the source table which may contain excluded rows.
    if ($Data[0] -is [Data.DataRow]) {
        $table = $Data[0].Table.Clone()
        foreach ($row in $Data) { $table.ImportRow($row) }
    } else {
        $table = [Data.DataTable]::new()
        foreach ($property in $Data[0].PSObject.Properties.Name) { $null = $table.Columns.Add($property, [object]) }
        foreach ($record in $Data) {
            $row = $table.NewRow()
            foreach ($column in $table.Columns) { $row[$column.ColumnName] = if ($null -eq $record.($column.ColumnName)) { [DBNull]::Value } else { $record.($column.ColumnName) } }
            $table.Rows.Add($row)
        }
    }
    $temp = Join-Path $Context.directory ([IO.Path]::GetRandomFileName())
    [IO.File]::Open($temp, [IO.FileMode]::CreateNew).Dispose()
    try {
        & $command $table | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
        if (!(Get-Item -LiteralPath $temp).Length) { throw 'Converter produced no content.' }
        [IO.File]::Move($temp, $path, [bool]$Options.overwrite)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    Get-Item -LiteralPath $path
}
Export-ModuleMember -Function Export-DataAgentCustom
