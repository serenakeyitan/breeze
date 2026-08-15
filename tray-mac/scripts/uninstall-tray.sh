#!/usr/bin/env bash
#
# Uninstall the breeze menu bar tray.
# Pass --purge to also wipe tray-state.json and tray-seen.json.
#

set -euo pipefail

PURGE=0
while [ "${1:-}" != "" ]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --help|-h)
      sed -n '3,6p' "$0"
      exit 0 ;;
    *) echo "ERROR: unknown flag '$1'"; exit 2 ;;
  esac
done

BREEZE_DIR="${BREEZE_DIR:-$HOME/.breeze}"
pkill -f "BreezeTray.app/Contents/MacOS/BreezeTray" 2>/dev/null || true

PLIST="${BREEZE_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/com.breeze.tray.plist"
if [ -f "$PLIST" ]; then
  if [ -z "${BREEZE_LAUNCH_AGENTS_DIR:-}" ]; then
    launchctl bootout "gui/$UID/com.breeze.tray" 2>/dev/null || true
  fi
  rm -f "$PLIST"
  echo "→ Removed launch agent."
fi

if [ -d "$BREEZE_DIR/tray" ]; then
  rm -rf "$BREEZE_DIR/tray"
  echo "→ Removed $BREEZE_DIR/tray."
fi

if [ "$PURGE" = "1" ]; then
  rm -f "$BREEZE_DIR/tray-state.json" "$BREEZE_DIR/tray-seen.json"
  echo "→ Purged tray state."
fi

echo "✓ breeze menu bar app uninstalled."
