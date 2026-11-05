# Provider boundaries are replaced only in this isolated test process.
Module Posh-SSH @'
$script:events = [Collections.Generic.List[object]]::new()
$script:fail = $false
$script:refuse = 0
function New-SFTPSession {
    param($ComputerName,$Credential,[switch]$ErrorOnUntrusted,$Port)
    if (!$ErrorOnUntrusted -or $Credential.UserName -ne 'synthetic') { throw 'connect arguments changed' }
    if ($script:refuse -gt 0) { $script:refuse--; throw 'Socket read operation has timed out' }
    $script:events.Add('connect'); [pscustomobject]@{SessionId=1}
}
function Set-SFTPItem {
    param($SFTPSession,$Path,$Destination,[switch]$Force)
    if ($script:fail) { throw 'upload failed' }
    $script:events.Add(@{Path=$Path;Destination=$Destination;Force=[bool]$Force})
}
function Remove-SFTPSession {
    param($SFTPSession)
    $script:events.Add('disconnect')
}
'@
$credential = [pscredential]::new('synthetic', (ConvertTo-SecureString 'synthetic' -AsPlainText -Force))
$cfg = Config 'sftp'
$cfg.dst = @{ adapter='sftp'; args=@{ connect=@{ComputerName='files.example.invalid';Credential=$credential;ErrorOnUntrusted=$true;Port=2222};send=@{Destination='/inbox';Force=$true} } }
$null = Run 'sftp' $cfg
$ssh = Get-Module -All Posh-SSH
$events = @(& $ssh { $script:events.ToArray() })
Assert ($events.Count -eq 3 -and $events[1].Destination -eq '/inbox' -and $events[1].Force -and $events[-1] -eq 'disconnect') 'SFTP arguments forwarded, session closed'
& $ssh { $script:fail=$true; $script:events.Clear() }
Refuses { Run 'sftp' $cfg } 'upload failed'
Assert (@(& $ssh { $script:events.ToArray() })[-1] -eq 'disconnect') 'SFTP cleanup after failure'
& $ssh { $script:fail=$false; $script:refuse=2; $script:events.Clear() }
$cfg.dst.args.delay = 0
$null = Run 'sftp' $cfg
$events = @(& $ssh { $script:events.ToArray() })
Assert ($events[0] -eq 'connect' -and $events.Count -eq 3) 'SFTP connect retried until it answered, one upload'
& $ssh { $script:refuse=3; $script:events.Clear() }
Refuses { Run 'sftp' $cfg } 'timed out'
Assert (@(& $ssh { $script:events.ToArray() }).Count -eq 0) 'SFTP connect gave up with the original error, nothing sent'

Add-Type @'
using System;
using System.IO;
using System.Net;
using System.Collections.Generic;
// Intentionally replace the legacy FTP factory used by the adapter.
#pragma warning disable SYSLIB0014
public class TestFtpFactory : IWebRequestCreate {
    public static List<TestFtpRequest> Requests = new List<TestFtpRequest>();
    public WebRequest Create(Uri uri) { var r = new TestFtpRequest(); Requests.Add(r); return r; }
}
public class TestFtpRequest : WebRequest {
    public static bool Fail;
    public bool EnableSsl {get;set;}
    public override string Method {get;set;}
    public override ICredentials Credentials {get;set;}
    public bool Aborted;
    public MemoryStream Bytes = new MemoryStream();
    public override Stream GetRequestStream() { return Bytes; }
    public override WebResponse GetResponse() { if (Fail) throw new IOException("transfer failed"); return new TestFtpResponse(); }
    public override void Abort() { Aborted=true; }
}
public class TestFtpResponse : WebResponse {}
'@
Assert ([Net.WebRequest]::RegisterPrefix('ftp://dataagent.invalid/',[TestFtpFactory]::new())) 'test FTP factory installed'
$cfg = Config 'ftp'
$cfg.dst = @{ adapter='ftp'; args=@{Uri='ftp://dataagent.invalid/incoming/';Credential=$credential} }
$null = Run 'ftp' $cfg
$request = [TestFtpFactory]::Requests[-1]
Assert (!$request.EnableSsl -and $request.Aborted -and $request.Credentials.UserName -eq 'synthetic') 'FTP selector and direct credential'
Assert ([Convert]::ToBase64String($request.Bytes.ToArray()) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes("$root/ftp/output.csv"))) 'FTP binary bytes'
$cfg.dst.adapter='ftps'
$null = Run 'ftp' $cfg
Assert ([TestFtpFactory]::Requests[-1].EnableSsl) 'FTPS selector enables TLS without a user toggle'
[TestFtpRequest]::Fail=$true
Refuses { Run 'ftp' $cfg } 'transfer failed'
Assert ([TestFtpFactory]::Requests[-1].Aborted) 'FTP releases request after failure'

# the http boundary is replaced for this process only; a function wins over the cmdlet of the same name
$global:httpPosts = [Collections.Generic.List[object]]::new()
$global:httpRefuse = $false
function global:Invoke-RestMethod {
    param($Method, $Uri, $Headers, $Body, $ContentType)
    if ($global:httpRefuse) { throw 'Response status code does not indicate success: 400 (Bad Request).' }
    $global:httpPosts.Add(@{ Method = $Method; Uri = $Uri; Headers = $Headers; Body = $Body; ContentType = $ContentType }); 'accepted'
}
$env:DATAAGENT_TEST_KEY = 'synthetic key'
$cfg = Config 'http'
$cfg.dst = @{ adapter = 'http'; args = @{ uri = 'https://dataagent.invalid/upload'; headers = @{ 'Api-Key' = 'env:DATAAGENT_TEST_KEY' }; nameheader = 'filename'; contenttype = 'text/plain' } }
$log = Run 'http' $cfg
$post = $global:httpPosts[-1]
Assert ($post.Method -eq 'Post' -and $post.Uri -eq 'https://dataagent.invalid/upload' -and $post.ContentType -eq 'text/plain') 'http posts to the uri with the content type'
Assert ($post.Headers['Api-Key'] -eq 'synthetic key' -and $post.Headers.filename -eq 'output.csv') 'http headers resolve env: and carry the file name'
Assert ($post.Body -eq (Get-Content "$root/http/output.csv" -Raw)) 'http body is the file text'
Assert (($log -join "`n") -match 'Response: accepted' -and ($log -join "`n") -notmatch 'synthetic key') 'http logs the answer, never the key'
$cfg.dst.args.Remove('nameheader')
$null = Run 'http' $cfg
Assert ($global:httpPosts.Count -eq 2 -and !$global:httpPosts[-1].Headers.ContainsKey('filename')) 'no nameheader, no file name header'
$global:httpRefuse = $true
Refuses { Run 'http' $cfg } '400'
Remove-Item function:global:Invoke-RestMethod
Remove-Variable httpPosts, httpRefuse -Scope Global
Remove-Item Env:DATAAGENT_TEST_KEY
