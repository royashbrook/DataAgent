# Provider boundaries are replaced only in this isolated test process.
Module Posh-SSH @'
$script:events = [Collections.Generic.List[object]]::new()
$script:fail = $false
function New-SFTPSession {
    param($ComputerName,$Credential,[switch]$ErrorOnUntrusted,$Port)
    if (!$ErrorOnUntrusted -or $Credential.UserName -ne 'synthetic') { throw 'connect arguments changed' }
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
