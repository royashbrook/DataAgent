function Send-DataAgentMail {
    [CmdletBinding(SupportsShouldProcess)]
    param([IO.FileInfo[]] $Data, [hashtable] $Options, [hashtable] $Context)
    $ErrorActionPreference = 'Stop'
    if (!$PSCmdlet.ShouldProcess(($Options.mail.to -join ','), $MyInvocation.MyCommand.Name)) { return }
    if (!$Options.mail -or !$Options.msgraph) { throw 'mail and msgraph options required.' }
    if ($Options.msgraph.ContainsKey('client_secret')) { throw 'client_secret belongs in the environment.' }
    if (!$env:CLIENT_SECRET) { throw 'CLIENT_SECRET required.' }
    foreach ($key in @('tenant_id', 'client_id')) {
        $id = [guid]::Empty
        if (![guid]::TryParse([string]$Options.msgraph[$key], [ref]$id)) { throw "Invalid $key." }
    }
    if (!$Options.mail.from -or !$Data.Count) { throw 'Mail sender and input files required.' }
    $mode = if ($Options.mode) { $Options.mode } else { 'separate' }
    if ($mode -notin @('separate', 'together', 'body')) { throw 'Invalid mail mode.' }
    if ($mode -eq 'body' -and $Data.Count -ne 1) { throw 'Body mode requires exactly one text or HTML file.' }
    $type = if ($Options.mail.bodyType) { $Options.mail.bodyType } else { 'Text' }
    if ($type -notin @('Text', 'HTML')) { throw 'Invalid mail bodyType.' }
    foreach ($file in $Data) { if ($file.Length -ge 3MB) { throw 'Mail input must be smaller than 3 MB; use a large-message adapter.' } }
    $groups = if ($mode -eq 'separate') { @($Data | ForEach-Object { @{ files = @($_) } }) } else { @(@{ files = $Data }) }
    $messages = foreach ($group in $groups) {
        $subject = if ($Options.mail.subject_format) { $Options.mail.subject_format -f $Context.runAt } else { $Options.mail.subject }
        $body = if ($mode -eq 'body') { Get-Content -LiteralPath $group.files[0].FullName -Raw } else { [string]$Options.mail.body }
        $message = @{ subject = $subject; body = @{ contentType = $type; content = $body } }
        foreach ($pair in @(@('to', 'toRecipients'), @('cc', 'ccRecipients'), @('bcc', 'bccRecipients'), @('replyTo', 'replyTo'))) {
            if ($Options.mail[$pair[0]]) { $message[$pair[1]] = @($Options.mail[$pair[0]] | ForEach-Object { @{ emailAddress = @{ address = $_ } } }) }
        }
        if (!$message.toRecipients -and !$message.ccRecipients -and !$message.bccRecipients) { throw 'Mail recipient required.' }
        if ($mode -ne 'body') {
            $message.attachments = @($group.files | ForEach-Object {
                @{ '@odata.type' = '#microsoft.graph.fileAttachment'; name = $_.Name; contentType = 'application/octet-stream'; contentBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName)) }
            })
        }
        $json = @{ message = $message } | ConvertTo-Json -Depth 12 -Compress
        if ([Text.Encoding]::UTF8.GetByteCount($json) -ge 4MB) { throw 'Mail request exceeds 4 MB; use a large-message adapter.' }
        @{ json = $json; paths = @($group.files.FullName) }
    }
    try {
        $auth = @{ client_id = $Options.msgraph.client_id; client_secret = $env:CLIENT_SECRET; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' }
        $token = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($Options.msgraph.tenant_id)/oauth2/v2.0/token" -Method Post -Body $auth -Verbose:$false -Debug:$false
        if (!$token.access_token) { throw 'No access token.' }
        $uri = 'https://graph.microsoft.com/v1.0/users/{0}/sendMail' -f [Uri]::EscapeDataString($Options.mail.from)
        foreach ($message in $messages) {
            $null = Invoke-RestMethod -Uri $uri -Method Post -Headers @{ Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($message.json)) -Verbose:$false -Debug:$false
            @{ state = 'submitted'; paths = $message.paths; to = $Options.mail.to }
        }
    } catch { throw 'Send-DataAgentMail failed; inspect the provider privately before retrying.' }
}
Export-ModuleMember -Function Send-DataAgentMail
