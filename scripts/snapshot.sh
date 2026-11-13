#!/bin/bash
# Regenerate the documentation screenshots with the real SwiftUI/AppKit window.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
./scripts/build.sh

rm -rf "$ROOT/docs/screenshots"
mkdir -p "$ROOT/docs/screenshots"

# 15 in-app states rendered through real NSHostingView windows.
"$ROOT/build/LexiNote.app/Contents/MacOS/LexiNote" --snapshot "$ROOT/docs/screenshots"

# The actual window, including native traffic lights and the unified titlebar.
rm -rf "$ROOT/build/runtime-vault"
LEXINOTE_STORE="$ROOT/build/runtime-vault" \
  "$ROOT/build/LexiNote.app/Contents/MacOS/LexiNote" --window-shot "$ROOT/docs/screenshots/00-native-window.png"

# The actual Settings modal sheet.
"$ROOT/build/LexiNote.app/Contents/MacOS/LexiNote" --settings-shot "$ROOT/docs/screenshots/16-settings-sheet.png"

rm -rf "$ROOT/build/runtime-vault"
echo "▸ Screenshots written to docs/screenshots"
