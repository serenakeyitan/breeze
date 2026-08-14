#!/usr/bin/env bash
#
# End-to-end tray checks:
#   1. Swift unit tests
#   2. Probe a live fake /inbox HTTP server (breeze JSON shape)
#   3. Parse a breeze-runner launchd plist
#   4. Install + uninstall into a temp BREEZE_DIR (no real login item)
#
# No first-tree paths or binaries are used.
#

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "OK: $*"; }

echo "== core self-test =="
swift build --package-path "$ROOT" --product BreezeTraySelfTest
SELFTEST="$(find "$ROOT/.build" -type f -name BreezeTraySelfTest -perm +111 | head -1)"
[ -n "$SELFTEST" ] && [ -x "$SELFTEST" ] || fail "BreezeTraySelfTest not built"
"$SELFTEST"

echo "== build probe + tray =="
swift build --package-path "$ROOT" --product breeze-tray-probe
PROBE="$(find "$ROOT/.build" -type f -name breeze-tray-probe -perm +111 | head -1)"
[ -n "$PROBE" ] && [ -x "$PROBE" ] || fail "breeze-tray-probe not built"

echo "== inbox fixture via probe =="
OUT="$("$PROBE" inbox "$ROOT/test/fixtures/inbox.json")"
echo "$OUT" | grep -q '^total=3$' || fail "expected total=3, got: $OUT"
echo "$OUT" | grep -q '^human=1$' || fail "expected human=1, got: $OUT"
echo "$OUT" | grep -q 'tornado-doc/tdoc	#42' || fail "expected human PR #42"
echo "$OUT" | grep -qv 'first-tree' || fail "fixture output mentioned first-tree"
pass "inbox probe"

echo "== plist probe =="
PLIST_OUT="$("$PROBE" parse-plist "$ROOT/test/fixtures/daemon.plist")"
echo "$PLIST_OUT" | grep -q '^repos=tornado-doc/tdoc$' || fail "plist repos: $PLIST_OUT"
echo "$PLIST_OUT" | grep -q '^http_port=7888$' || fail "plist port: $PLIST_OUT"
pass "plist probe"

echo "== start-args never include first-tree =="
START="$("$PROBE" start-args tornado-doc/tdoc)"
echo "$START" | grep -q 'start --allow-repo tornado-doc/tdoc' || fail "start-args: $START"
echo "$START" | grep -Eiq 'first-tree|tree-repo' && fail "start-args leaked first-tree: $START"
pass "start-args"

echo "== live HTTP inbox e2e =="
PORT=$((18000 + RANDOM % 1000))
python3 - "$PORT" "$ROOT/test/fixtures/inbox.json" <<'PY' &
import http.server, sys, pathlib
port = int(sys.argv[1])
body = pathlib.Path(sys.argv[2]).read_bytes()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?", 1)[0] in ("/inbox", "/"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path.split("?", 1)[0] == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass

http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break
  sleep 0.1
done
LIVE="$("$PROBE" inbox "http://127.0.0.1:$PORT/inbox")"
echo "$LIVE" | grep -q '^human=1$' || fail "live inbox: $LIVE"
pass "live HTTP inbox"

echo "== install / uninstall e2e =="
WORKDIR="$(mktemp -d /tmp/breeze-tray-e2e.XXXXXX)"
export BREEZE_DIR="$WORKDIR/home"
export BREEZE_LAUNCH_AGENTS_DIR="$WORKDIR/LaunchAgents"
mkdir -p "$BREEZE_DIR" "$BREEZE_LAUNCH_AGENTS_DIR"

BREEZE_TRAY_BUILD_QUIET=1 "$ROOT/scripts/build-tray-app.sh" debug
"$ROOT/scripts/install-tray.sh" --no-launch --no-autostart --source "$ROOT/.build/BreezeTray.app"
[ -x "$BREEZE_DIR/tray/BreezeTray.app/Contents/MacOS/BreezeTray" ] || fail "app binary missing"
INFO="$(plutil -extract CFBundleDisplayName raw "$BREEZE_DIR/tray/BreezeTray.app/Contents/Info.plist")"
[ "$INFO" = "breeze" ] || fail "display name is $INFO, want breeze"
plutil -p "$BREEZE_DIR/tray/BreezeTray.app/Contents/Info.plist" | grep -Eiq 'first-tree|FirstTree' && fail "Info.plist still has first-tree"
! grep -Riq 'first-tree' "$BREEZE_DIR/tray/BreezeTray.app/Contents/Info.plist" || fail "Info.plist first-tree string"

# also write an autostart plist without touching the real LaunchAgents
"$ROOT/scripts/install-tray.sh" --no-launch --source "$ROOT/.build/BreezeTray.app"
[ -f "$BREEZE_LAUNCH_AGENTS_DIR/com.breeze.tray.plist" ] || fail "launch agent missing"
grep -q 'com.breeze.tray' "$BREEZE_LAUNCH_AGENTS_DIR/com.breeze.tray.plist" || fail "wrong launch agent label"
! grep -Eiq 'first-tree' "$BREEZE_LAUNCH_AGENTS_DIR/com.breeze.tray.plist" || fail "launch agent mentions first-tree"

"$ROOT/scripts/uninstall-tray.sh" --purge
[ ! -d "$BREEZE_DIR/tray" ] || fail "tray dir still present after uninstall"
[ ! -f "$BREEZE_LAUNCH_AGENTS_DIR/com.breeze.tray.plist" ] || fail "launch agent still present"
pass "install/uninstall"

# brand grep on sources
if grep -Riq 'first-tree\|FirstTree\|github scan' "$ROOT/Sources" "$ROOT/scripts" "$ROOT/Package.swift"; then
  fail "source still mentions first-tree / github scan"
fi
pass "no first-tree strings in tray sources"

rm -rf "$WORKDIR"
echo
echo "ALL E2E CHECKS PASSED"
