# DataAgent

Get data. Format a file. Use data. Record what happened.

DataAgent is a PowerShell module for scheduled file feeds. A feed repository needs
only settings and a tiny job; the module owns dispatch, logging, cleanup, and run
receipts. No service, AI model, or agent framework is required.

## Try it without contacting a database or sending mail

Requires PowerShell 7.4 or later.

```powershell
Install-Module DataAgent -RequiredVersion 0.3.0 -Scope CurrentUser
```

Copy [examples/settings.json](examples/settings.json) and
[examples/job.ps1](examples/job.ps1) into a new directory. The entire job is:

```powershell
param([ValidateSet('Mock','ExportOnly','Live')][string]$Mode='Mock')
Import-Module DataAgent -RequiredVersion 0.3.0 -ErrorAction Stop
Invoke-DataAgent -SettingsPath "$PSScriptRoot/settings.json" -Mode $Mode
```

Run `./job.ps1`. Mock is the default: five packaged synthetic rows, a temporary
output directory, and a local recording instead of external delivery. The command
returns one finalized receipt object. Logs use the information stream.

```powershell
$receipt = ./job.ps1
$receipt | Select-Object status, rowCount, artifacts, deliveries
Get-DataAgentReceipt -WorkingDirectory $PWD
# Use your own synthetic input for a parity check:
Invoke-DataAgent -SettingsPath ./settings.json -FixturePath ./my-fixture.csv
```

The packaged fixture is generic, not a sample of any particular production feed.

## How it fits together

```text
your scheduler → job.ps1 + settings.json → Invoke-DataAgent
                                            │
                   cleanup → get data → format file → use data
                                │            │           │
                            SQL / CSV       CSV      mail / recording
                                            │
                                artifact hash + run receipt
```

| Mode | Source | Delivery | Default output |
| --- | --- | --- | --- |
| Mock (default) | Packaged CSV or `-FixturePath` | Local mock recording | New temporary directory |
| ExportOnly | Configured source, including real SQL | None | New temporary directory |
| Live | Configured source | Configured destination | Settings directory |

**ExportOnly can read a real database.** Mock is the no-external-I/O rehearsal.
SQL text is trusted configuration: read-only behavior is not enforced. A query
with writes can change the database even in ExportOnly.
All modes run retention in their output directory; choose a dedicated directory.
`-WorkingDirectory` must exist. `-RunAt` controls the artifact name and log date,
not the current-time retention cutoff.

`Invoke-DataAgent -SettingsPath ./settings.json -Mode Live -WhatIf` previews the
whole run without executing it: no source query, callbacks, cleanup, output,
receipt, or send. `-Confirm` asks once before the run; approval covers its nested
stages. The pipeline and each state-changing exported adapter also support these
parameters when called directly. WhatIf returns no receipt, since nothing ran.

## Configure a feed

The `etl` object selects built-in adapters, never evaluated code:

```json
"etl": { "source": "sql", "format": "csv", "destination": "email" }
```

- Source: `sql`, using the `sql` arguments in settings, or `csv`, using
  `"csv": { "path": "../inputs/source.csv" }` relative to the settings file.
- Format: `csv`. Column order is preserved; PowerShell's native `Export-Csv`
  handles quoting and escaping. Encoding is UTF-8 without BOM; newline follows
  the host OS. Compare bytes on your intended runner before cutting over.
- Destination: `email`, using `mail` and `msgraph` settings, or `recording`, which
  always records a mock outcome locally and never sends anything.
- `keepdays`: positive integer. `purgefiles`: comma-separated output patterns
  passed to Clear-Files. `file_format`: one filename with a .NET date placeholder.

CSV input must be outside the output directory so cleanup cannot remove it.
Existing artifact names refuse overwrite or resend. The default timestamp has
second precision: serialize runs and choose a naming pattern appropriate to the feed.

### Optional live adapters

The core installs pinned `Add-PrefixForLogging` 1.0.0.2 and `Clear-Files` 1.0.0.0.
Install only the live adapters you use:

```powershell
Install-Module SqlServer -RequiredVersion 22.4.5.1 -Scope CurrentUser
Install-Module Send-FileViaEmail -RequiredVersion 2.0.0.0 -Scope CurrentUser
```

Inject `CONNECTION_STRING` and `CLIENT_SECRET` through your scheduler's secret
store into the process environment. Never put their values in settings or source
control. The `sql` object may contain `Query` or a settings-relative `InputFile`;
it must not contain `ConnectionString`. Keep `msgraph.client_secret` empty.
The mail adapter uses the configured Microsoft Graph application and recipients.

Review the config and provider permissions, rehearse on the intended runner, then
explicitly select `./job.ps1 -Mode Live`. Installing the module schedules nothing.

## Receipts, retention, and failure

Receipts and mock recordings live under the user's LocalApplicationData/DataAgent
directory, keyed by the resolved settings-directory path. Set the absolute
`DATAAGENT_STATE_ROOT` environment variable to choose another root. They do not
accumulate in the feed repository. Output artifacts and daily logs stay in the
chosen output directory. Temporary mock/export-only output is not automatically
removed by a later run in a different temporary directory.

Receipts include a run ID, mode, row count, phase timestamps, artifact byte count
and SHA-256, plus artifact/delivery arrays. Version 0.3 supports **one artifact and
one destination per run**; the array schema is not a multi-output promise.

- Empty input is `idle`: no artifact or delivery.
- `submitted` means the adapter call returned, not that someone received a file.
- `confirmed` requires an adapter acknowledgment. Mock IDs remain under
  `mockEvidence`, never presented as real provider IDs.
- Exceptions persist an error receipt and propagate to the caller. Unhandled
  exceptions give a nonzero script exit.
- An interrupted `delivery-attempted` run is ambiguous. Inspect it before retrying.
  There is no automatic retry, resume, exactly-once delivery, or cross-run lock.

Each run removes only owned expired receipts/recordings for its state directory,
using `keepdays`. Output retention follows `purgefiles`. Protect local data with
OS permissions: files and receipts are not encrypted, logs can contain errors
from custom adapters, and receipts contain paths and delivery metadata.

## Custom stages

`Invoke-DataAgentPipeline` exposes `-Extract` (get data), `-Transform` (format), and
`-Deliver` (use data) scriptblocks. Extract receives a context; Transform receives
rows and context and must write `context.ArtifactPath`; Deliver receives context
and returns one outcome dictionary. Its default mode is ExportOnly; Run/Mock require
a delivery adapter. Custom scriptblocks are trusted code, not sandboxed plugins.

The built-in helpers are `Invoke-DataAgentSql`, `Export-DataAgentCsv`,
`Send-DataAgentMail`, and `Write-DataAgentRecording`. Their module-specific nouns
avoid collisions with other modules' commands.

Naming follows Microsoft's [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands):
Invoke runs synchronously; Start would imply asynchronous work. SQL uses Invoke
because it executes caller-supplied statements, not an enforced read-only query.
State-changing commands implement [ShouldProcess](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/creating-a-cmdlet-that-modifies-the-system)
for WhatIf and Confirm. Mock and ExportOnly are execution modes, not substitutes for
WhatIf.

## Development and release checks

```powershell
pwsh -NoProfile -File tests/acceptance.ps1
```

Install the two pinned core dependencies first, or pass `-DependencyPath` pointing
at a saved module directory. Tests use synthetic rows and local recording only,
exercise a fresh-process consumer, and compare CSV bytes against native
Export-Csv on the executing OS. CI runs on Linux, macOS, and Windows. On macOS,
`bash tests/offline-macos.sh` additionally tests under a network-denying sandbox.

`prepare.ps1` creates an optional offline bundle with pinned dependencies and a
two-file consumer; run the bundle's `try.ps1` to smoke-test it. Normal users can
install from the Gallery instead.

This is an early release. Offline tests do not certify live SQL, email, or a
production feed migration. Those need environment-specific validation.

License: [MIT](LICENSE).
