#!/bin/bash
# Builds a universal (arm64 + x86_64) AppMixer.app and packages it into a
# distributable DMG. Each arch is built separately and merged with lipo, so a
# full Xcode install is not required. The app is ad-hoc signed (not notarized),
# so first launch on another Mac needs a right-click -> Open.
set -euo pipefail
cd "$(dirname "$0")"

APP="AppMixer.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
DMG="AppMixer-${VERSION}.dmg"

echo "==> Building arm64"
swift build -c release --arch arm64
ARM64_BIN="$(swift build -c release --arch arm64 --show-bin-path)/AppMixer"

echo "==> Building x86_64"
swift build -c release --arch x86_64
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/AppMixer"

echo "==> Merging into a universal binary"
mkdir -p .build/universal
lipo -create "$ARM64_BIN" "$X86_BIN" -output .build/universal/AppMixer
echo "    archs: $(lipo -archs .build/universal/AppMixer)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/universal/AppMixer "$APP/Contents/MacOS/AppMixer"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "==> Building $DMG"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "AppMixer ${VERSION}" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "==> Done: $(pwd)/$DMG"
