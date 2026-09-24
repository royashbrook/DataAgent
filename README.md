# DataAgent

the repeated part of a feed job: get data, format it, send it. use the tools you already use.

```powershell
Install-Module DataAgent -RequiredVersion 0.6.0 -Scope CurrentUser
```

## the job

```powershell
Import-Module DataAgent -RequiredVersion 0.6.0
Invoke-DataAgent "$PSScriptRoot/settings.json"
```

that is the whole job's `.ps1`. the run works in the settings file's folder. a secret stays out of the file: write `"env:NAME"` as the value and it is read from the environment when the run starts, and `{ "username": ..., "password": ... }` becomes a PSCredential. a script can still pass a hashtable instead of a path. [settings.json](examples/settings.json) and [job.ps1](examples/job.ps1) show SQL + CSV + email.

## what it supports

read the [capability brief](DataAgent/CAPABILITIES.md) for the config contract, all nine built-in adapters, owned options versus helper pass-throughs, custom scripts, dependencies and limits. the same file ships in the gallery module, so an agent or person can inspect the installed contract without reading code or running a job.

the runner sets location to the settings file's folder, the calling script's directory, or the config's `directory` (for a module that wraps the runner), logs to screen and `yyyyMMdd.log`, cleans up when configured, then gets, formats and sends. empty results send nothing. `-WhatIf` skips the whole run. custom adapters need no core edit.

**0.4 is a breaking change from 0.3.** use `Invoke-DataAgent -Config` and src/fmt/dst. Pipeline/Extract/Transform/Deliver and provider/receipt helpers are removed. installation does not migrate jobs.

## test and adoption

optional `DataAgent.Test` exports Test-DataAgent: a synthetic CSV input through the real runner and formatter in a temporary directory. `-FixturePath` selects another synthetic fixture. no production mock mode.

from a checkout, add the repo and `testing` directory to PSModulePath. install the helper versions listed in `.github/workflows/test.yml`, then run:

```powershell
./tests/acceptance.ps1
./tests/capabilities.ps1
./tests/package.ps1
```

acceptance uses real logging, cleanup, email formatting and XLSX helpers; SQL/SFTP/FTP/HTTP boundaries are replaced inside the test process. `bash tests/offline-macos.sh` additionally denies network access at the OS boundary. these are not live-provider tests.

the capability check compares adapter names and direct Options property reads (including CSV's local copy) with the brief. helper-owned splatted options stay the helper's contract; dynamically computed keys or new aliases need a corresponding check. the package check publishes to a temporary local repository, saves the package back and verifies the exact brief. neither check proves provider semantics.

before adopting a feed, prove output/layout, runner identity and dependencies, cleanup and scoped provider behavior. nothing here changes a live feed.

MIT. see [LICENSE](LICENSE).
