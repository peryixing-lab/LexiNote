#!/bin/bash
# Package 知萤 LexiNote.app into a distributable macOS .dmg disk image.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

./scripts/build.sh

APP="$ROOT/build/LexiNote.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")
DMG_NAME="LexiNote-${VERSION}-arm64.dmg"
DMG_PATH="$ROOT/build/$DMG_NAME"
STAGING="$ROOT/build/.dmg-staging"

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/LexiNote.app"
ln -s /Applications "$STAGING/Applications"

echo "▸ Creating ${DMG_PATH}..."
hdiutil create \
  -volname "知萤 LexiNote ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING"
ls -lh "$DMG_PATH"
echo "▸ Packaged $DMG_PATH"
