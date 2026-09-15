function Send-DataAgentMail {
    [CmdletBinding(SupportsShouldProcess)]
    param([IO.FileInfo[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess(($Options.mail.to -join ','), $MyInvocation.MyCommand.Name)) { return }
    if ($Options.msgraph.client_secret) { throw 'client_secret belongs in the environment.' }
    if (!$env:CLIENT_SECRET) { throw 'CLIENT_SECRET required.' }
    $graph = $Options.msgraph.Clone()
    $graph.client_secret = $env:CLIENT_SECRET
    $cfg = [pscustomobject]@{ mail = [pscustomobject]$Options.mail; msgraph = [pscustomobject]$graph }
    foreach ($file in $Data) {
        Push-Location -LiteralPath $file.DirectoryName
        try { $null = Send-FileViaEmail $file.Name $cfg }
        catch { throw 'Send-DataAgentMail failed; inspect the provider privately.' }
        finally { Pop-Location }
        @{ state = 'submitted'; path = $file.FullName; to = $Options.mail.to }
    }
}
Export-ModuleMember -Function Send-DataAgentMail
