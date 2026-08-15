# breeze menu bar tray

Native macOS menu bar app for the breeze daemon. Shows items labeled
`breeze:human`, and Pause / Resume of `breeze-runner`.

This is a thin client of the daemon — the same `127.0.0.1:<port>/inbox`
endpoint as the dashboard. The daemon is authoritative.

## Requirements

- macOS 13+
- Swift toolchain (Xcode Command Line Tools is enough)
- `breeze-runner` on PATH, or the launchd plist written by `breeze-runner start`

## Build / install

```bash
cd tray-mac
./scripts/build-tray-app.sh release
./scripts/install-tray.sh
```

Uninstall: `./scripts/uninstall-tray.sh` (`--purge` also drops `~/.breeze/tray-state.json`).

## Tests

```bash
cd tray-mac
swift test
./test/e2e.sh
```
