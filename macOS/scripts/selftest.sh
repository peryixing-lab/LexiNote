#!/bin/bash
# Exercise persistence, frontmatter, search, backlinks, graph, trash and maps
# against a throwaway folder.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
./scripts/build.sh
rm -rf "$ROOT/build/selftest-vault"
"$ROOT/build/LexiNote.app/Contents/MacOS/LexiNote" --selftest "$ROOT/build/selftest-vault"
