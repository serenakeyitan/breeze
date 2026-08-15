#!/usr/bin/env bash
#
# Install the breeze menu bar tray to $BREEZE_DIR/tray/ (default ~/.breeze/tray).
#
#   --no-launch       Install but don't open the app
#   --no-autostart    Don't register a LaunchAgent
#   --source <path>   Path to BreezeTray.app (default: build inline)
#

set -euo pipefail

LAUNCH=1
AUTOSTART=1
SOURCE_APP=""

while [ "${1:-}" != "" ]; do
  case "$1" in
    --no-launch)    LAUNCH=0; shift ;;
    --no-autostart) AUTOSTART=0; shift ;;
    --source)       SOURCE_APP="$2"; shift 2 ;;
    --help|-h)
      sed -n '3,10p' "$0"
      exit 0 ;;
    *)
      echo "ERROR: unknown flag '$1'"
      exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAY_DIR="$(dirname "$SCRIPT_DIR")"
BREEZE_DIR="${BREEZE_DIR:-$HOME/.breeze}"
DEST_DIR="$BREEZE_DIR/tray"
DEST_APP="$DEST_DIR/BreezeTray.app"

if [ -z "$SOURCE_APP" ]; then
  SOURCE_APP="$TRAY_DIR/.build/BreezeTray.app"
  if [ ! -d "$SOURCE_APP" ]; then
    echo "→ Building tray app first..."
    BREEZE_TRAY_BUILD_QUIET=1 "$SCRIPT_DIR/build-tray-app.sh" release
  fi
fi

if [ ! -d "$SOURCE_APP" ]; then
  echo "ERROR: source .app not found at $SOURCE_APP"
  exit 1
fi

echo "→ Installing to $DEST_APP..."
mkdir -p "$DEST_DIR"
pkill -f "BreezeTray.app/Contents/MacOS/BreezeTray" 2>/dev/null || true
sleep 0.3
rm -rf "$DEST_APP"
cp -R "$SOURCE_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

if [ "$AUTOSTART" = "1" ]; then
  PLIST="${BREEZE_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/com.breeze.tray.plist"
  echo "→ Writing launch agent at $PLIST..."
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST_BODY
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.breeze.tray</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>$DEST_APP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST_BODY
  if [ -z "${BREEZE_LAUNCH_AGENTS_DIR:-}" ] && command -v launchctl >/dev/null; then
    launchctl bootout "gui/$UID/com.breeze.tray" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$PLIST" 2>/dev/null || true
  fi
fi

if [ "$LAUNCH" = "1" ]; then
  echo "→ Launching..."
  open "$DEST_APP"
fi

echo "✓ breeze menu bar app installed."
