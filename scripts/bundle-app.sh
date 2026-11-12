#!/usr/bin/env bash
# Build a release binary and wrap it in Veil.app (LSUIElement menubar app). Optionally embeds the model.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Veil.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Veil "$APP/Contents/MacOS/Veil"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ "${EMBED_MODEL:-0}" = "1" ]; then ./scripts/download-model.sh "$APP/Contents/Resources/rampart"; fi
codesign --force --deep --sign - "$APP"
echo "Built $APP"
