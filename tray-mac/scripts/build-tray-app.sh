#!/usr/bin/env bash
#
# Build BreezeTray.app from the SwiftPM executable.
#
#   ./scripts/build-tray-app.sh           # debug
#   ./scripts/build-tray-app.sh release   # release
#

set -euo pipefail

CONFIG="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$TRAY_DIR"

echo "→ Building Swift target ($CONFIG)..."
if [ "$CONFIG" = "release" ]; then
  swift build -c release --product BreezeTray
  BUILD_BIN=".build/release/BreezeTray"
else
  swift build --product BreezeTray
  BUILD_BIN="$(find .build -type f -name BreezeTray -perm +111 | head -1)"
fi

if [ ! -f "$BUILD_BIN" ]; then
  echo "ERROR: build did not produce a binary at $BUILD_BIN"
  exit 1
fi

APP=".build/BreezeTray.app"
echo "→ Assembling .app bundle at $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_BIN" "$APP/Contents/MacOS/BreezeTray"

TRAY_VERSION="0.1.0"
if [ -f "$TRAY_DIR/../VERSION" ]; then
  TRAY_VERSION="$(tr -d ' \n' < "$TRAY_DIR/../VERSION")"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BreezeTray</string>
  <key>CFBundleDisplayName</key><string>breeze</string>
  <key>CFBundleIdentifier</key><string>com.breeze.tray</string>
  <key>CFBundleVersion</key><string>${TRAY_VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${TRAY_VERSION}</string>
  <key>CFBundleExecutable</key><string>BreezeTray</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "✓ Built $APP"
if [ -t 1 ] && [ "${BREEZE_TRAY_BUILD_QUIET:-0}" = "0" ]; then
  echo "To run:  open $APP"
fi
