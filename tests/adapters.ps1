# Runs inside acceptance.ps1, with its isolated paths, assertions, and fake HTTP.
foreach ($quoting in @('Always', 'AsNeeded', 'Never', 'Strip')) {
    $cfg = Config "csv-$quoting"; $cfg.transform.options.quoting = $quoting
    $r = Run "csv-$quoting" $cfg
    $useQuotes = if ($quoting -eq 'Strip') { 'Always' } else { $quoting }
    $expected = Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv" | ConvertTo-Csv -NoTypeInformation -UseQuotes $useQuotes
    if ($quoting -eq 'Strip') { $expected = $expected | ForEach-Object { $_.Replace('"', '') } }
    $expected | Set-Content "$root/quoting.csv" -Encoding utf8NoBOM
    Assert ((Get-FileHash $r.artifacts[0].path).Hash -eq (Get-FileHash "$root/quoting.csv").Hash) "$quoting CSV byte parity"
}

$cfg = Config 'custom'
$converter = @'
function ConvertTo-Custom([Data.DataTable] $dt) {
    if ($dt.Columns.Count -lt 2 -or !$dt.Rows.Count) { throw 'not the legacy DataTable contract' }
    foreach ($row in $dt.Rows) { '{0}|{1}' -f $row[0], $row[1] }
}
Export-ModuleMember -Function ConvertTo-Custom
'@
$converter | Set-Content "$root/custom/ConvertTo-Custom.psm1"
$converterHash = (Get-FileHash "$root/custom/ConvertTo-Custom.psm1").Hash
$cfg.transform = @{ module = 'DataAgent.Custom'; version = '0.4.0'; command = 'Export-DataAgentCustom'; options = @{ converter = './ConvertTo-Custom.psm1'; file_format = 'output.txt' } }
$r = Run 'custom' $cfg
Assert ($r.status -eq 'completed' -and $r.rows -eq 5 -and (Get-FileHash "$root/custom/ConvertTo-Custom.psm1").Hash -eq $converterHash) 'existing converter receives DataTable unchanged on disk'
$context = @{ directory = "$root/custom/output"; configDirectory = "$root/custom"; runAt = Get-Date }
$table = [Data.DataTable]::new()
$null = $table.Columns.Add('value', [int]); $null = $table.Columns.Add('text', [string])
$null = $table.Rows.Add(12, 'keep'); $null = $table.Rows.Add(99, 'excluded')
$file = Export-DataAgentCustom -Data @($table.Rows[0]) -Options @{ converter = './ConvertTo-Custom.psm1'; file_format = 'selected.txt' } -Context $context
Assert ((Get-Content $file.FullName -Raw).Trim() -eq '12|keep') 'custom adapter preserves selected rows, excludes rest of original table'
Refuses { Export-DataAgentCustom -Data @($table.Rows[0]) -Options @{ converter = './ConvertTo-Custom.psm1'; file_format = 'selected.txt' } -Context $context } 'Output exists'
$file = Export-DataAgentCustom -Data @($table.Rows[1]) -Options @{ converter = './ConvertTo-Custom.psm1'; file_format = 'selected.txt'; overwrite = $true } -Context $context
Assert ((Get-Content $file.FullName -Raw).Trim() -eq '99|excluded') 'custom explicit overwrite'
'function ConvertTo-Custom($dt) { throw "converter failed" }; Export-ModuleMember -Function ConvertTo-Custom' | Set-Content "$root/custom/fail.psm1"
$hash = (Get-FileHash $file.FullName).Hash
Refuses { Export-DataAgentCustom -Data @($table.Rows[0]) -Options @{ converter = './fail.psm1'; file_format = 'selected.txt'; overwrite = $true } -Context $context } 'converter failed'
Assert ((Get-FileHash $file.FullName).Hash -eq $hash) 'failed custom conversion preserves previous output'

$cfg = Config 'xlsx'
$cfg.transform = @{ module = 'DataAgent.Xlsx'; version = '0.4.0'; command = 'Export-DataAgentXlsx'; options = @{ file_format = 'output.xlsx'; excel = @{ WorksheetName = 'Rows'; TableStyle = 'Medium6'; NoNumberConversion = @('*') } } }
$r = Run 'xlsx' $cfg
$rows = @(Import-Excel -Path $r.artifacts[0].path -WorksheetName Rows)
$expectedRows = @(Import-Csv "$repo/testing/DataAgent.Test/synthetic.csv")
Assert ($rows.Count -eq 5 -and ($rows | ConvertTo-Json -Compress) -eq ($expectedRows | ConvertTo-Json -Compress)) 'real XLSX cell values, order, quoting and multiline text'
$cfg.transform.options.overwrite = $true; $r = Run 'xlsx' $cfg
Assert (@(Import-Excel $r.artifacts[0].path).Count -eq 5) 'XLSX explicit replacement does not append'
$cfg.transform.options.excel.Path = 'outside.xlsx'
Refuses { Run 'xlsx' $cfg } 'XLSX option reserved'

$mailModule = Get-Module DataAgent.Mail
$mail = @{ mail = @{ from = 'sender@example.invalid'; to = @('to@example.invalid'); cc = @('cc@example.invalid'); bcc = @('bcc@example.invalid'); replyTo = @('reply@example.invalid'); subject = 'literal {subject}'; body = 'hello'; bodyType = 'Text' }; msgraph = @{ tenant_id = '00000000-0000-0000-0000-000000000001'; client_id = '00000000-0000-0000-0000-000000000002' } }
$files = @(Get-Item "$root/extension/output/first.json", "$root/extension/output/second.json")
$env:CLIENT_SECRET = 'test-only'
& $mailModule { $script:messages.Clear() }
$outcomes = @(Send-DataAgentMail -Data $files -Options $mail -Context @{ runAt = Get-Date })
$messages = @(& $mailModule { $script:messages.ToArray() })
Assert ($messages.Count -eq 2 -and $outcomes.Count -eq 2 -and $messages[0].message.attachments.Count -eq 1) 'separate one-file emails'
Assert ($messages[0].message.subject -eq 'literal {subject}' -and $messages[0].message.ccRecipients.Count -eq 1 -and $messages[0].message.bccRecipients.Count -eq 1 -and $messages[0].message.replyTo.Count -eq 1) 'mail subject and recipient options preserved'
Assert ($messages[0].message.attachments[0].name -eq $files[0].Name -and $messages[0].message.attachments[0].contentBytes -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($files[0].FullName))) 'mail attachment name and bytes'
& $mailModule { $script:messages.Clear() }
$mail.mode = 'together'
$outcomes = @(Send-DataAgentMail -Data $files -Options $mail -Context @{ runAt = Get-Date })
$messages = @(& $mailModule { $script:messages.ToArray() })
Assert ($messages.Count -eq 1 -and $outcomes.Count -eq 1 -and $messages[0].message.attachments.Count -eq 2) 'one email with multiple attachments'
& $mailModule { $script:messages.Clear() }
$mail.mode = 'body'; $mail.mail.bodyType = 'HTML'; $mail.mail.subject_format = 'report {0:yyyy-MM-dd}'
'<p>hello é</p>' | Set-Content "$root/body.html" -Encoding utf8NoBOM
$null = Send-DataAgentMail -Data @(Get-Item "$root/body.html") -Options $mail -Context @{ runAt = [datetime]'2026-01-02' }
$messages = @(& $mailModule { $script:messages.ToArray() })
Assert ($messages.Count -eq 1 -and !$messages[0].message.attachments -and $messages[0].message.body.content -eq (Get-Content "$root/body.html" -Raw) -and $messages[0].message.subject -eq 'report 2026-01-02') 'HTML body and formatted subject, no attachment'
Refuses { Send-DataAgentMail -Data $files -Options $mail -Context @{} } 'exactly one'
$null = Send-DataAgentMail -Data $files -Options @{} -Context @{} -WhatIf
Assert (@(& $mailModule { $script:messages.ToArray() }).Count -eq 1) 'mail WhatIf does not authenticate or send'
$requests = & $mailModule { $script:requests }
$stream = [IO.File]::Create("$root/large.txt"); $stream.SetLength(3MB); $stream.Dispose()
Refuses { Send-DataAgentMail -Data @(Get-Item "$root/large.txt") -Options $mail -Context @{} } 'smaller than 3 MB'
$stream = [IO.File]::Create("$root/medium.txt"); $stream.SetLength(2MB); $stream.Dispose()
$mail.mode = 'together'
Refuses { Send-DataAgentMail -Data @((Get-Item "$root/medium.txt"), (Get-Item "$root/medium.txt")) -Options $mail -Context @{} } 'exceeds 4 MB'
Assert ((& $mailModule { $script:requests }) -eq $requests) 'oversize mail refuses before authentication'
& $mailModule { $script:failMail = $true }
Refuses { Send-DataAgentMail -Data $files -Options $mail -Context @{ runAt = Get-Date } } '^Send-DataAgentMail failed; inspect the provider privately before retrying\.$'
& $mailModule { $script:failMail = $false }
$env:CLIENT_SECRET = ''

Module Posh-SSH 3.2.7 @'
$script:events = [Collections.Generic.List[object]]::new()
$script:fail = $false
function New-SFTPSession {
    [CmdletBinding()] param($ComputerName, $Port, $Credential, [switch]$ErrorOnUntrusted, $ConnectionTimeout, $OperationTimeout)
    if (!$ErrorOnUntrusted -or $Credential.UserName -ne 'test-only') { throw 'unsafe connection' }
    $script:events.Add('connect'); [pscustomobject]@{ SessionId = 7 }
}
function Set-SFTPItem {
    [CmdletBinding()] param($SFTPSession, $Destination, $Path, [switch]$Force)
    if ($script:fail) { throw 'upload failed' }
    $script:events.Add(@{ path = $Path; overwrite = [bool]$Force })
}
function Remove-SFTPSession {
    [CmdletBinding()] param($SFTPSession)
    $script:events.Add('disconnect')
}
'@
Import-Module DataAgent.Sftp -RequiredVersion 0.4.0
$ssh = Get-Module Posh-SSH
$env:FTP_USER = 'test-only'; $env:FTP_PASS = 'test-only'
$options = @{ host = 'dataagent.invalid'; path = '/inbox'; overwrite = $true }
$outcomes = @(Send-DataAgentSftp -Data $files -Options $options -Context @{})
$events = @(& $ssh { $script:events.ToArray() })
Assert ($outcomes.Count -eq 2 -and $events.Count -eq 4 -and $events[-1] -eq 'disconnect' -and $events[1].overwrite) 'SFTP two files with explicit overwrite and session cleanup'
& $ssh { $script:events.Clear(); $script:fail = $true }
Refuses { Send-DataAgentSftp -Data $files -Options $options -Context @{} } 'Send-DataAgentSftp failed'
Assert (@(& $ssh { $script:events.ToArray() })[-1] -eq 'disconnect') 'SFTP closes session after failed upload'
$null = Send-DataAgentSftp -Data $files -Options @{} -Context @{} -WhatIf

# Replace the FTP request factory only in this isolated test process, not the adapter.
Add-Type @'
using System;
using System.IO;
using System.Net;
using System.Collections.Generic;
// The adapter intentionally uses the legacy FTP factory; this test replaces it.
#pragma warning disable SYSLIB0014
public class TestFtpFactory : IWebRequestCreate {
    public static List<TestFtpRequest> Requests = new List<TestFtpRequest>();
    public WebRequest Create(Uri uri) { var r = new TestFtpRequest(); Requests.Add(r); return r; }
}
public class TestFtpRequest : WebRequest {
    public static bool Fail;
    public bool EnableSsl {get;set;}
    public bool UsePassive {get;set;}
    public bool UseBinary {get;set;}
    public bool KeepAlive {get;set;}
    public int ReadWriteTimeout {get;set;}
    public override int Timeout {get;set;}
    public override string Method {get;set;}
    public override ICredentials Credentials {get;set;}
    public bool Aborted;
    public MemoryStream Bytes = new MemoryStream();
    public override Stream GetRequestStream() { return Bytes; }
    public override WebResponse GetResponse() { if (Fail) throw new IOException("test failure"); return new TestFtpResponse(); }
    public override void Abort() { Aborted = true; }
}
public class TestFtpResponse : WebResponse { public int StatusCode {get {return 226;}} }
'@
Assert ([Net.WebRequest]::RegisterPrefix('ftp://dataagent.invalid/', [TestFtpFactory]::new())) 'isolated FTP factory installed'
Import-Module DataAgent.Ftp -RequiredVersion 0.4.0
$outcomes = @(Send-DataAgentFtp -Data $files -Options $options -Context @{})
Assert ($outcomes.Count -eq 2 -and [TestFtpFactory]::Requests[0].EnableSsl -and [TestFtpFactory]::Requests[0].Aborted) 'FTPS is default, final response read, resources released'
Assert ([Convert]::ToBase64String([TestFtpFactory]::Requests[0].Bytes.ToArray()) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($files[0].FullName))) 'FTP binary upload bytes'
$options.tls = $false
$null = Send-DataAgentFtp -Data @($files[0]) -Options $options -Context @{}
Assert (![TestFtpFactory]::Requests[-1].EnableSsl) 'plain FTP requires explicit false'
$options.overwrite = $false
Refuses { Send-DataAgentFtp -Data $files -Options $options -Context @{} } 'explicit overwrite'
$options.overwrite = $true; [TestFtpRequest]::Fail = $true
Refuses { Send-DataAgentFtp -Data $files -Options $options -Context @{} } 'Send-DataAgentFtp failed'
Assert ([TestFtpFactory]::Requests[-1].Aborted) 'FTP failure releases request'
$null = Send-DataAgentFtp -Data $files -Options @{} -Context @{} -WhatIf
$env:FTP_USER = ''; $env:FTP_PASS = ''
