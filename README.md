# DataAgent

the repeated part of a feed job: get data, format it, send it. use the tools you already use.

**0.4.0 is a breaking change from 0.3.0.** migrate jobs to `Invoke-DataAgent -Config` and the `src` / `fmt` / `dst` contract below. `Invoke-DataAgentPipeline` and the old provider/receipt helpers are removed. installing this version does not migrate existing jobs.

```powershell
Install-Module DataAgent -RequiredVersion 0.4.1 -Scope CurrentUser
```

## the job

```powershell
Import-Module DataAgent -RequiredVersion 0.4.1
Invoke-DataAgent -Config $cfg
```

put these calls in the job's `.ps1`. `$cfg` is a hashtable supplied by that script. load JSON if useful, then add runtime values such as credentials. DataAgent assumes no environment variable names and does not print configuration. [settings.json](examples/settings.json) and [job.ps1](examples/job.ps1) show SQL + CSV + email.

the module sets location once to the calling script's folder, not its own folder or the shell's starting directory, and stays there, including on failure. this is deliberate job-runner behavior; direct interactive calls are not supported. it tees ordinary output and `l` messages to the screen and appends `yyyyMMdd.log` there. a terminating error is also recorded, then rethrown so `pwsh -File job.ps1` exits nonzero. no receipt directory, hash ledger, scheduler, or retry engine.

`Invoke-DataAgent -Config $cfg -WhatIf` skips the entire run, including adapter imports and cleanup. only this public entrypoint advertises WhatIf. adapters are internal scripts, not independently exported commands or packages.

## adapters

each descriptor is `{ "adapter": "name", "args": { ... } }`. `src` and `fmt` take one descriptor; `dst` takes one or a list, or can be omitted to format only. every destination receives all generated files, in sequence; a failure stops the job. no conditional routing or best-effort branches are implied.

| folder | adapters | existing operation |
|---|---|---|
| `src` | `sql`, `csv` | Invoke-Sqlcmd, Import-Csv |
| `fmt` | `csv`, `xlsx`, `custom` | ConvertTo-Csv + Set-Content, Export-Excel, ConvertTo-Custom |
| `dst` | `email`, `sftp`, `ftp`, `ftps` | Send-FileViaEmail, Posh-SSH, .NET FTP |

no records means `No data available` and no formatting or sending. the configured filename is passed to the formatter and destination, not returned as a FileInfo object. built-ins use ordinary direct-write behavior, including overwrite, rather than staging or refusing existing output. a formatter that cannot produce its configured output should throw; missing files fail when the destination reads them. run in a dedicated job directory without overlapping workers, just like a standalone feed job.

### source

`src/sql` forwards `args` to Invoke-Sqlcmd and emits rows from DataTable results; `src/csv` forwards them to Import-Csv. empty SQL tables produce no records, so the runner skips formatting and delivery. relative paths resolve in the job directory. pass a connection string, integrated-auth settings, or other supported arguments directly; credentials need not come from a particular environment variable. keep secrets out of committed config and logs.

### format

`file_format`, when provided, is formatted with the run's current date and supplied as `fmt.args.Path`. otherwise supply Path yourself.

- `csv`: Path, optional Encoding (default utf8NoBOM), and ConvertTo-Csv arguments such as UseQuotes (Always/AsNeeded/Never), Delimiter, NoHeader. `StripQuotes: true` reproduces removing every double quote, including quotes in data. unquoted modes can be lossy with commas/newlines; use the feed's required format. source column order is retained.
- `xlsx`: arguments pass through to Export-Excel, including Path, WorksheetName, AutoSize, and TableStyle. workbook behavior is the helper's, not a new overwrite policy. verify cells/layout, not ZIP hashes. AutoSize may need native support on non-Windows hosts.
- `custom`: `args.Module` names the existing module exporting `ConvertTo-Custom($dt)`; `args.Path` is the output. the bridge passes a DataTable and writes returned text as UTF-8 without BOM. no converter rewrite required.

### destination

- `email`: one filename, one call to Send-FileViaEmail. `args` pass through (`cfg`, optional `contentType`); the adapter supplies `file`. multiple filenames throw before any email call, never fan out into separate messages. use a filename in the job folder: the existing helper uses that literal value as both the path and attachment name. no new multi-attachment/body API or client-side size policy. provider limits still apply.
- `sftp`: `args.connect` passes to New-SFTPSession and `args.send` to Set-SFTPItem. supply Credential, ComputerName, Destination, and the host-key/overwrite policy you actually intend. the session closes even on failure. prefer verified trusted hosts; `Force` on connection bypasses host-key validation.
- `ftp` / `ftps`: independent scripts, no shared dispatch or TLS toggle. args are `Uri` (remote directory, `ftp://host/path/`) and `Credential` (PSCredential or .NET NetworkCredential). FTPS enables explicit TLS on the FTP connection; implicit FTPS is not supported. plain FTP sends credentials and data unencrypted. both upload with normal replacement behavior.

```powershell
$cfg.dst = @{
    adapter = 'sftp'
    args = @{
        connect = @{ ComputerName = 'files.example.invalid'; Credential = $credential; ErrorOnUntrusted = $true }
        send = @{ Destination = '/incoming'; Force = $true }
    }
}
```

### custom adapter

instead of a built-in name, set `adapter` to a `.ps1` path (relative to the job directory or absolute). the runner maps src/fmt/dst to their script paths; no resolver helper or registry. every script receives `-Data` and `-Options`. sources return records. formatters write `Options.Path`; destinations receive those configured filename strings as Data. a custom formatter can accept a list of paths, but must write each one, and email still accepts only one. keep progress off the source's success stream. adapters must not change location: the log and job paths stay rooted in the calling script's folder. config selects executable code and is trusted like the job script itself.

## dependencies and cleanup

install only the helpers the job uses. the runner never installs anything. tested versions: Add-PrefixForLogging 1.0.0.2, Clear-Files 1.0.0.0, SqlServer 22.4.5.1, Send-FileViaEmail 2.0.0.0, ImportExcel 7.8.10, Posh-SSH 3.2.7. PowerShell 7.4+. pin these in the runner's provisioning, not in every adapter.

Add-PrefixForLogging is loaded first for `l`. when `purgefiles` is configured, Clear-Files is loaded and receives the config (`keepdays`, `purgefiles`) before adapter loading or querying. its deletion behavior is unchanged: give it a dedicated output directory and deliberate patterns. no additional cleanup/state policy is imposed.

## test and adoption

optional `DataAgent.Test` exports Test-DataAgent: a synthetic CSV input through the real runner and formatter, in a temporary directory. `-FixturePath` selects another synthetic fixture. no production mock mode.

from a checkout, add the repo and `testing` directory to PSModulePath. install the helper versions listed in `.github/workflows/test.yml`, then run `pwsh -NoProfile -File tests/acceptance.ps1`. it uses real logging, cleanup, email formatting and XLSX helpers; SQL/SFTP/FTP/HTTP boundaries are replaced inside the test process. `bash tests/offline-macos.sh` additionally denies network access at the OS boundary. these are not live-provider tests.

only Invoke-DataAgent is exported; config uses src/fmt/dst, adapters are bundled, and receipts are removed. earlier receipt files are left untouched. old Mode/Extract/Transform/Deliver calls must be rewritten for these adapters; optional synthetic tests live in DataAgent.Test. cache filtering, acknowledgment/retry policies, conditional routing, and multi-attachment/body email are not implemented. before adopting any feed, prove its output/layout, runner identity and dependencies, cleanup, and scoped provider behavior. nothing here changes a live feed.

MIT. see [LICENSE](LICENSE).
