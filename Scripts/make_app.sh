#!/bin/bash
# Assemble FOGNote.app from the swift-build executable.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/FOGNote"
APP="build/FOGNote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/FOGNote"
cp Assets/Info.plist "$APP/Contents/Info.plist"
if [ -f Assets/FOGNote.icns ]; then
  cp Assets/FOGNote.icns "$APP/Contents/Resources/FOGNote.icns"
fi

codesign --force --deep --sign - "$APP"
echo "Built $APP"
