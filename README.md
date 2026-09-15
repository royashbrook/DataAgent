# DataAgent

run a feed from config. keep the source, format, and destination outside the runner.

**0.4.0 is a review candidate, not a published upgrade.** the published 0.3.0 API is documented at [v0.3.0](https://github.com/royashbrook/DataAgent/tree/v0.3.0).

```text
settings.json + job.ps1
          |
    Invoke-DataAgent
          |
   source -> records -> transform -> files -> destination(s)
          |
     log + receipt
```

## modules

| module | job | dependencies |
|---|---|---|
| DataAgent | run configured commands, cleanup, receipts | none |
| DataAgent.Sql | `Invoke-DataAgentSql` | SqlServer 22.4.5.1 |
| DataAgent.Csv | `Import-DataAgentCsv`, `Export-DataAgentCsv` | none |
| DataAgent.Mail | `Send-DataAgentMail` | Send-FileViaEmail 2.0.0.0 |
| DataAgent.Test | `Test-DataAgent`, fixture source, recording destination | DataAgent + DataAgent.Csv |

PowerShell 7.4+. install only the adapters a job uses. the runner never installs modules.

## try the candidate

from this checkout:

```powershell
$env:PSModulePath = (@($PWD.Path, "$PWD/adapters", "$PWD/testing", $env:PSModulePath) -join [IO.Path]::PathSeparator)
Import-Module DataAgent.Test -RequiredVersion 0.4.0
Test-DataAgent
# or: Test-DataAgent -FixturePath /path/to/your/synthetic.csv
```

this creates a temporary output directory and returns a receipt. it uses the real CSV adapter, but no SQL, mail, credentials, or network. the packaged fixture is generic; use your own synthetic rows to check a feed's bytes.

## run a job

[settings.json](examples/settings.json) selects SQL, CSV, and mail. [job.ps1](examples/job.ps1) is the whole consumer:

```powershell
Import-Module DataAgent -RequiredVersion 0.4.0 -ErrorAction Stop
Invoke-DataAgent -SettingsPath "$PSScriptRoot/settings.json"
```

that is a real run. first install the configured adapter versions and their dependencies. supply `CONNECTION_STRING` and `CLIENT_SECRET` through the job environment, never settings. SQL options are passed to `Invoke-Sqlcmd`; relative `InputFile` paths resolve beside settings. mail options contain `mail` and `msgraph`, without `client_secret`.

`-WhatIf` reads and checks the config but imports no adapters and performs no cleanup, query, write, or delivery. omit `destination` to export without sending. `-WorkingDirectory` selects an existing output folder; otherwise output goes beside settings.

## add an adapter

an adapter is an exported command in an ordinary, explicitly installed PowerShell module. no registry, base class, or core edit. each config descriptor has `module`, `version`, `command`, and optional `options`. `destination` accepts one descriptor or a list.

all commands receive `-Data`, `-Options` (hashtable), and `-Context` (hashtable):

| role | receives | returns on the success stream |
|---|---|---|
| source | empty data | records; none means idle |
| transform | source records | one or more nonempty regular `FileInfo` objects; none means idle |
| destination | all generated files | outcome dictionaries with `state`; `confirmed` also requires `acknowledgment` |

context contains `runId`, `runAt`, `directory`, `configDirectory`, and `stateDirectory`. keep logs off the success stream. throw to fail the run. adapters own their provider checks, credential handling, format, and overwrite policy. configuration selects executable code: review it like a script, not untrusted input.

for example, a separately installed formatter can expose:

```powershell
function Export-Example {
    param($Data, [hashtable] $Options, [hashtable] $Context)
    $path = Join-Path $Context.directory $Options.filename
    if (Test-Path -LiteralPath $path) { throw 'output exists' }
    $Data | ConvertTo-Json | Set-Content -LiteralPath $path
    Get-Item -LiteralPath $path
}
Export-ModuleMember -Function Export-Example
```

select that module and command under `transform`. the tests prove external adapters work with unchanged core bytes, including multiple files and destinations.

## operations

- logs are `<timestamp> <module>\<command> <status>` in `yyyyMMdd.log`, also on the information stream.
- receipts record the current command **before** invoking it, then file hashes and returned outcomes. mail reports `submitted`, not provider-confirmed delivery. an interrupted or failed call can have an unknown external outcome. inspect before retrying; there is no automatic retry or resume.
- `Get-DataAgentReceipt -SettingsPath ./settings.json` reads history. receipts live outside the feed under local application data, keyed by the resolved settings path. `DATAAGENT_STATE_ROOT` overrides the root with an absolute path.
- `keepdays` controls receipt retention and aged output matching `purgefiles`. cleanup runs after formatting, or on an idle source. current artifacts, settings, and the current log are protected. CSV refuses existing output by default; `transform.options.overwrite: true` allows fixed-name replacement, staged beside the target before moving into place. CSV input must be outside the output directory.
- destinations run sequentially and receive all files. the first failure stops the run. no per-file routing, best-effort branch, scheduler, or retry engine is included. disable overlapping scheduled runs.

## upgrading from 0.3.0

this is a breaking candidate. replace fixed `sql`/`mail` options with the descriptors in the example, install the chosen adapters, and remove `Mode`. `Test-DataAgent` moves to the optional test module; no `Mock` or `FixturePath` branch remains in the runner. `Get-DataAgentReceipt` now takes `SettingsPath`, not `WorkingDirectory`; old receipt files remain where they were and are not migrated. log text and cleanup timing changed, so check any log consumer and retention expectations before switching.

the supplied adapters cover SQL or CSV input, native quoted CSV output, and mail submission. quote-stripped text, custom formats, XLSX, SFTP/FTP, Oracle, and conditional routing need their own adapters or a separate workflow. having an extension point is not evidence that those feeds are migration-ready.

## verify

`pwsh -NoProfile -File tests/acceptance.ps1` runs without network or real providers. tests include byte parity, external adapters, receipt failures, retention, `WhatIf`, and staged package imports. SQL/mail calls use test-only stubs; this is not a live-provider certification. CI runs on Windows, macOS, and Linux. on macOS, `tests/offline-macos.sh` additionally denies network access at the OS boundary.

before adopting a feed: compare its exact output on the target OS, pin the runner's module versions, check logs and cleanup, then approve a scoped provider test. **legacy log-consumer compatibility is an open adoption blocker**, not a completed check: the new format has idle/completion signals but not the old strings or elapsed-time column. no live feed changes are part of this candidate.

MIT. see [LICENSE](LICENSE).
