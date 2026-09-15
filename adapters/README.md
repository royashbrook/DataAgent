# adapter options

all descriptors use `module`, exact `version`, `command`, and `options`. examples below replace only that part of settings. these are 0.4.0 review candidates, not published packages.

## coverage

| operation | adapter | offline proof / remaining boundary |
|---|---|---|
| SQL input | Sql | command options tested; target query and authentication still need proof |
| CSV input/output | Csv | native bytes for Always, AsNeeded, Never, and legacy Strip |
| custom text | Custom | unchanged `ConvertTo-Custom($dt)`, selected DataTable rows, exact fixture bytes |
| XLSX | Xlsx | real workbook values and sheet options; target sizing still needs proof |
| SFTP | Sftp | command arguments, all files, cleanup; actual server/key still needs proof |
| explicit FTPS / plain FTP | Ftp | TLS selection, binary bytes, cleanup; actual server/TLS still needs proof |
| email one file per message | Mail / separate | request payloads and attachment bytes |
| email multiple files together | Mail / together | one request containing all attachments |
| email text or HTML body | Mail / body | generated file becomes body, no attachment |

mail proofs replace Graph locally. real submission, permissions, recipients, size, and rendering require a scoped provider test. no row in this table certifies an entire feed fleet.

## CSV

```json
{
  "module": "DataAgent.Csv", "version": "0.4.0", "command": "Export-DataAgentCsv",
  "options": { "file_format": "{0:yyyyMMdd}-feed.csv", "quoting": "Always" }
}
```

`quoting` defaults to `Always`. `AsNeeded` and `Never` are PowerShell's native `ConvertTo-Csv -UseQuotes` modes. `Strip` reproduces `ConvertTo-Csv` followed by removing **every** double quote, including quotes inside data. it is deliberately destructive, not interchangeable with `Never`. neither unquoted mode escapes embedded delimiters or newlines safely; choose it only for a format that requires it. output is UTF-8 without BOM, with native platform line endings.

## existing custom converters

```json
{
  "module": "DataAgent.Custom", "version": "0.4.0", "command": "Export-DataAgentCustom",
  "options": { "converter": "./ConvertTo-Custom.psm1", "file_format": "{0:yyyyMMdd}-feed.txt" }
}
```

the path resolves beside settings. the module must export `ConvertTo-Custom($dt)` and return text on its success stream. the bridge passes a DataTable and writes the result as UTF-8 without BOM. the converter itself stays unchanged. DataRow input preserves its column types; other records become object columns. logs belong off the success stream.

for a formatter that already writes files, skip this bridge: select your own exported adapter command under `transform`, returning `FileInfo` objects. return several for a multi-artifact job. the runner still needs no edits.

## XLSX

```json
{
  "module": "DataAgent.Xlsx", "version": "0.4.0", "command": "Export-DataAgentXlsx",
  "options": {
    "file_format": "{0:yyyyMMdd}-feed.xlsx",
    "excel": { "WorksheetName": "Rows", "TableStyle": "Medium6", "NoNumberConversion": ["*"] }
  }
}
```

`excel` passes options to ImportExcel's `Export-Excel`. the adapter owns Path, ExcelPackage, InputObject, PassThru, Show, KillExcel, Append, and NoClobber; do not supply them. `AutoSize` can require extra native support on non-Windows hosts. prove it on the actual runner if used. compare cell values and formatting, not ZIP-file hashes. embedded CRLF text becomes LF inside the workbook, matching native Export-Excel.

all three formatters refuse existing output unless `overwrite: true` is explicit. replacement is staged; converter/export failure leaves the old file intact.

## SFTP and FTPS

```json
{
  "module": "DataAgent.Sftp", "version": "0.4.0", "command": "Send-DataAgentSftp",
  "options": { "host": "files.example.invalid", "path": "/incoming", "overwrite": true }
}
```

credentials come from `FTP_USER` and `FTP_PASS`, not settings. SFTP defaults to port 22 and refuses unknown host keys. enroll the verified key for the actual scheduler account in Posh-SSH's trusted-host store before adoption. there is no automatic key acceptance. it refuses replacement unless `overwrite: true`.

for **explicit FTPS**, select `DataAgent.Ftp` / `Send-DataAgentFtp` with the same options. it defaults to port 21, TLS enabled, passive binary transfer, and normal certificate validation. implicit FTPS (usually port 990) is not supported. plain FTP requires explicit `tls: false`; credentials and data then travel unencrypted.

FTP requires `overwrite: true` because STOR can replace a remote file and cannot guarantee no-clobber. this adapter uses the legacy .NET FtpWebRequest API; it is isolated here so a replacement never needs a runner edit. both transports send all files to one directory and report submission, not downstream processing.

## mail

```json
{
  "module": "DataAgent.Mail", "version": "0.4.0", "command": "Send-DataAgentMail",
  "options": {
    "mode": "together",
    "msgraph": { "tenant_id": "TENANT_GUID", "client_id": "APP_CLIENT_GUID" },
    "mail": {
      "from": "sender@example.invalid", "to": ["recipient@example.invalid"],
      "cc": [], "bcc": [], "replyTo": [],
      "subject_format": "Feed {0:yyyy-MM-dd}", "body": "Files attached.", "bodyType": "Text"
    }
  }
}
```

set `CLIENT_SECRET` through the environment. use literal `subject`, or explicit `subject_format` with the run date. `to`, `cc`, `bcc`, and `replyTo` accept address lists.

- `separate` (default): one message per file.
- `together`: all files in one message.
- `body`: exactly one UTF-8 text/HTML artifact becomes the message body, with no attachment. use `bodyType: "HTML"` when appropriate. a custom formatter can generate that artifact.

attachment modes use `mail.body` as optional static body text. each input must be under 3 MB and each serialized request under 4 MB; larger messages need an upload-session adapter. [Graph acceptance does not establish delivery](https://learn.microsoft.com/en-us/graph/api/user-sendmail?view=graph-rest-1.0). outcomes say `submitted`. if one message fails after another succeeded, the call fails and its external outcome is ambiguous: inspect before retrying.

## adoption gate

map every feed's source, format, destinations, overwrite rules, empty-data behavior, cleanup, and failure policy before fleet adoption. conditional file routing, per-trip batching, and best-effort delivery branches need an explicit custom adapter or separate workflow; they are not silently flattened into the generic runner. verify exact text bytes or workbook semantics on the target OS, module versions, scheduler identity, trusted hosts, scoped provider calls, and log consumers. a successful pilot does not waive the remaining feeds.
