#!/usr/bin/env bash
# Mechanical checks for onboard journeys J3/J5/J9/J12 apply behavior.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLY="$ROOT/bin/breeze-onboard-apply"
fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "OK: $*"; }

TMP=$(mktemp -d /tmp/breeze-journey.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
export BREEZE_DIR="$TMP"

# J9 / J5: refuse all and globs
"$APPLY" --allow-repo all --no-start && fail "accepted all" || pass "J5/J9 reject all"
"$APPLY" --allow-repo 'acme/*' --no-start && fail "accepted glob" || pass "J9 reject glob"

# J12: config only
"$APPLY" --allow-repo tornado-doc/tdoc --no-start --no-tray
grep -q 'tornado-doc/tdoc' "$BREEZE_DIR/config.yaml" || fail "missing repo"
grep -q 'poll_interval: 600' "$BREEZE_DIR/config.yaml" || fail "poll not 600"
! grep -Eq 'all' "$BREEZE_DIR/config.yaml" || fail "all leaked"
[ ! -d "$BREEZE_DIR/tray" ] || fail "tray installed without opt-in"
pass "J12 config only, no tray"

# J1-shaped apply flags (no start in this sandbox)
"$APPLY" --allow-repo tornado-doc/tdoc --no-tray --no-start
pass "J1 flags without tray"

echo ALL JOURNEY MECHANICS PASSED
