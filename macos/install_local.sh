#!/bin/bash
# Build, sign with the persistent local identity (keeps macOS privacy
# permissions such as "Local Network" across rebuilds) and install.
set -e
cd "$(dirname "$0")/.."
ID="AndroidLink Local Signing"
APP=build/macos/Build/Products/Release/androidlink.app
[ "$1" = "--no-build" ] || flutter build macos --release
codesign --force --deep --sign "$ID" --entitlements macos/Runner/Release.entitlements "$APP"
osascript -e 'quit app "AndroidLink"' 2>/dev/null || true
sleep 1; pkill -f /Applications/AndroidLink.app 2>/dev/null || true
rm -rf /Applications/AndroidLink.app
ditto "$APP" /Applications/AndroidLink.app
open /Applications/AndroidLink.app
