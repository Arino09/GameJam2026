#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$PROJECT_DIR"
rm -rf "$PROJECT_DIR/build/web"
mkdir -p build/web
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --editor --import --quit
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-release Web build/web/index.html
for file in index.html index.js index.wasm index.pck; do
  test -s "build/web/$file" || { echo "Missing Web export: $file" >&2; exit 1; }
done
python3 tools/version-web-assets.py
touch build/web/.nojekyll
printf 'Web build ready: %s/build/web/index.html\n' "$PROJECT_DIR"
