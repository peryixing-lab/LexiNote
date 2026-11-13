#!/bin/bash
# Build with Xcode's build system. Useful when developing in Xcode or when
# you want the asset catalog (app icon) compiled by actool.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

xcodebuild \
  -project LexiNote.xcodeproj \
  -scheme LexiNote \
  -configuration Release \
  -derivedDataPath "$ROOT/build/xcode-derived" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$ROOT/build/xcode-derived/Build/Products/Release/LexiNote.app"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "▸ Built $APP"
