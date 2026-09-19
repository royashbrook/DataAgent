# DataAgent capabilities

one public command: `Invoke-DataAgent -Config $cfg`. call it from a job `.ps1` in PowerShell 7.4+. it changes to the calling script's directory and stays there, including on failure. `-WhatIf` skips the entire run, including imports and cleanup.

## config and flow

`src` and `fmt` each take `{ adapter = 'name'; args = @{ ... } }`. `dst` takes one descriptor, a list, or nothing for format-only. `args` become the adapter's `Options` hashtable. pass credentials at runtime; no environment variable names are assumed. keep secrets out of committed config and logs.

the runner loads Add-PrefixForLogging, optionally calls Clear-Files with `purgefiles` / `keepdays`, then runs source -> formatter -> destinations. no records means `No data available`, no file and no send. destinations run in order; a failure stops the job. ordinary output and `l` messages append to `yyyyMMdd.log` and the screen. terminating errors are logged and rethrown.

`file_format`, if present, is formatted with the run's current date and overrides `fmt.args.Path`. otherwise supply Path yourself. the configured filename goes to the formatter and destinations, not a FileInfo object. built-ins write directly and overwrite. use a dedicated job directory without overlapping workers.

## built-ins

owned options are the keys the adapter interprets itself. other arguments belong to the named helper, not a second DataAgent API. the table is checked against adapter files and direct option reads in CI; that does not prove helper behavior or every possible argument value.

| adapter | owned options | helper / pass-through |
|---|---|---|
| `src/sql` | none | `Invoke-Sqlcmd` |
| `src/csv` | none | `Import-Csv` |
| `fmt/csv` | `Path`, `Encoding`, `StripQuotes` | `ConvertTo-Csv` |
| `fmt/xlsx` | none | `Export-Excel` |
| `fmt/custom` | `Module`, `Path` | `ConvertTo-Custom` |
| `dst/email` | none | `Send-FileViaEmail` |
| `dst/sftp` | `connect`, `send` | `New-SFTPSession`, `Set-SFTPItem` |
| `dst/ftp` | `Uri`, `Credential` | `FtpWebRequest` |
| `dst/ftps` | `Uri`, `Credential` | `FtpWebRequest` |

- **sql:** arguments pass to Invoke-Sqlcmd, including connection strings and authentication settings. DataTable results emit their rows; empty tables emit nothing. multiple result sets are flattened, not separate artifacts. use compatible schemas.
- **csv source:** arguments pass directly to Import-Csv. relative paths resolve in the job directory.
- **csv format:** Path is the output; Encoding defaults to utf8NoBOM. all remaining arguments pass to ConvertTo-Csv, including Delimiter, UseQuotes and NoHeader. StripQuotes removes *every* double quote, including data. unquoted modes can lose meaning with commas/newlines. source column order is retained.
- **xlsx:** all arguments pass to Export-Excel, including Path and layout options. verify cells/layout, not ZIP hashes. AutoSize may need native support on non-Windows hosts.
- **custom format bridge:** Module is a path to a module exporting `ConvertTo-Custom($dt)`. the bridge passes a DataTable and saves returned text to Path as UTF-8 without BOM. this bridge is for existing text converters, not binary ZIP output.
- **email:** one filename, one Send-FileViaEmail call with `file` supplied by the adapter. other arguments pass through, such as `cfg` and `contentType`. multiple filenames throw before sending, never fan out. use a filename in the job directory: the helper uses it as both path and attachment name. no body/multi-attachment API or new size policy is provided here.
- **sftp:** connect is splatted to New-SFTPSession, send to Set-SFTPItem. the adapter supplies the session and local Path; the session closes even on failure. choose the intended host-key/overwrite policy. connection Force bypasses host-key validation; prefer verified trusted hosts.
- **ftp / ftps:** independent scripts. Uri is a remote directory (`ftp://host/path/`); Credential is a PSCredential or .NET NetworkCredential. uploads replace normally. FTPS uses explicit TLS, not implicit FTPS. plain FTP sends credentials and data unencrypted.

## custom adapters

set `adapter` to a `.ps1` path, relative to the job directory or absolute. no registration or core edit. each script receives `-Data` and `-Options`:

- source: return records on the success stream. keep progress off that stream.
- formatter: write Options.Path. a custom script can write a ZIP or a list of paths; it must produce every configured output and throw on failure.
- destination: Data is the configured filename string or strings. every destination receives all of them; built-in email still accepts only one.

adapters must not change location. config selects executable code and is trusted like the job script itself. these scripts are internal, not independently exported commands or modules.

## dependencies and limits

the runner does not install dependencies. tested versions: Add-PrefixForLogging 1.0.0.2, Clear-Files 1.0.0.0, SqlServer 22.4.5.1, Send-FileViaEmail 2.0.0.0, ImportExcel 7.8.10, Posh-SSH 3.2.7. install only the helpers the job uses and pin provisioning versions.

no cache/deduplication, acknowledgment tracking, retry engine, receipts, scheduler or conditional routing. cleanup remains Clear-Files behavior; choose deliberate patterns in a dedicated output directory. provider limits still apply. before adopting a feed, prove its output/layout, runner identity, dependencies, cleanup and scoped delivery behavior. this brief is not a live-provider test.

0.4 replaces the old Pipeline/Extract/Transform/Deliver API with Config and src/fmt/dst. installation does not migrate jobs. optional synthetic exercises are in DataAgent.Test, not production mock modes.

read this installed file without importing or running the module:

```powershell
$module = Get-Module DataAgent -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
Get-Content (Join-Path $module.ModuleBase CAPABILITIES.md) -Raw
```
