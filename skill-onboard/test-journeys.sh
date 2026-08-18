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

"$APPLY" --allow-repo tornado-doc/tdoc --runtime grok --no-start --no-tray
grep -qx 'grok' "$BREEZE_DIR/runtime" || fail "runtime file"
pass "runtime grok saved"

"$APPLY" --allow-repo tornado-doc/tdoc --runtime nope --no-start && fail "accepted bad runtime" || pass "reject bad runtime"

# Author-follow is optional and off by default
! grep -q 'author_follow_repos:' "$BREEZE_DIR/config.yaml" || fail "author-follow on by default"
pass "author-follow omitted stays off"

"$APPLY" --allow-repo tornado-doc/tdoc,serenakeyitan/tokentorrent --author-follow-repo serenakeyitan/tokentorrent --no-start --no-tray
grep -q 'serenakeyitan/tokentorrent' "$BREEZE_DIR/config.yaml" || fail "follow repo missing"
grep -A1 'author_follow_repos:' "$BREEZE_DIR/config.yaml" | grep -q 'serenakeyitan/tokentorrent' || fail "follow list missing"
pass "author-follow explicit list"

"$APPLY" --allow-repo tornado-doc/tdoc,serenakeyitan/tokentorrent --no-start --no-tray
grep -A1 'author_follow_repos:' "$BREEZE_DIR/config.yaml" | grep -q 'serenakeyitan/tokentorrent' || fail "follow not preserved"
pass "omitting author-follow preserves the switch"

"$APPLY" --allow-repo tornado-doc/tdoc,serenakeyitan/tokentorrent --no-author-follow --no-start --no-tray
! grep -q 'author_follow_repos:' "$BREEZE_DIR/config.yaml" || fail "follow not cleared"
pass "J16 --no-author-follow clears the switch"

"$APPLY" --allow-repo tornado-doc/tdoc --author-follow-repo serenakeyitan/tokentorrent --no-start && fail "accepted follow outside allowlist" || pass "follow must be on the allowlist"
"$APPLY" --allow-repo tornado-doc/tdoc --author-follow-repo all --no-start && fail "accepted follow all" || pass "reject author-follow all"

echo ALL JOURNEY MECHANICS PASSED
