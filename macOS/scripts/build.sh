#!/bin/bash
# Build 知萤 LexiNote for Apple Silicon. Uses swiftc directly so the build works
# without an Xcode project; Xcode is still useful for editing.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/LexiNote.app"
CACHE="$ROOT/.build-cache"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"

SOURCES=$(find "$ROOT/Sources/LexiNoteMac" -name '*.swift' | sort)

echo "▸ Compiling $(echo "$SOURCES" | wc -l | tr -d ' ') Swift files (arm64, macOS 14+)…"
TMPDIR="$CACHE" xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -target arm64-apple-macos14.0 \
  -disable-sandbox \
  -module-cache-path "$CACHE/modcache" \
  -framework SwiftUI -framework AppKit -framework WebKit \
  $SOURCES \
  -o "$APP/Contents/MacOS/LexiNote"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$APP/Contents/Resources/plugin-runtime"
cp -R "$ROOT/Resources/plugin-runtime" "$APP/Contents/Resources/plugin-runtime"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "▸ Built $APP"
