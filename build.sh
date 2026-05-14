#!/bin/bash
# Builds AppMixer and assembles a .app bundle you can double-click or move to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="AppMixer.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/AppMixer"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/AppMixer"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"

echo "==> Done: $(pwd)/$APP"
echo "    Run with:  open $(pwd)/$APP"
