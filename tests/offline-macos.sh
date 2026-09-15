#!/usr/bin/env bash
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "$0")" && pwd)
pwsh_path=$(command -v pwsh)
profile='(version 1)(allow default)(deny network*)'
# Prove the guard, not just the workload's willingness to stay offline.
sandbox-exec -p "$profile" "$pwsh_path" -NoLogo -NoProfile -Command '
try {
    $socket = [Net.Sockets.TcpClient]::new()
    $socket.Connect("127.0.0.1", 9)
    throw "Network guard did not refuse"
} catch {
    $socketError = $_.Exception
    while ($socketError.InnerException) { $socketError = $socketError.InnerException }
    if ($socketError -is [Net.Sockets.SocketException] -and $socketError.NativeErrorCode -in @(1, 13)) {
        "PASS: network guard denies loopback socket"
    } else { throw }
} finally { if ($socket) { $socket.Dispose() } }
'
exec sandbox-exec -p "$profile" "$pwsh_path" -NoLogo -NoProfile -File "$test_dir/acceptance.ps1" "$@"
