#!/usr/bin/env bash
# Linux x86_64 installation from official Godot releases, verified with SHA-512.
set -euo pipefail
VERSION="${GODOT_VERSION:-4.7.2}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${GODOT_INSTALL_DIR:-${RUNNER_TEMP:-$PROJECT_DIR/.godot/tools}/godot/$VERSION}"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION.stable"
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'This installer requires Linux x86_64.' >&2
  exit 1
fi
for command in curl unzip sha512sum awk; do
  command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
mkdir -p "$INSTALL_DIR" "$TEMPLATE_DIR"
cd "$INSTALL_DIR"
ENGINE="Godot_v${VERSION}-stable_linux.x86_64.zip"
TEMPLATES="Godot_v${VERSION}-stable_export_templates.tpz"
BASE_URL="https://github.com/godotengine/godot-builds/releases/download/${VERSION}-stable"
for file in "$ENGINE" "$TEMPLATES" SHA512-SUMS.txt; do
  curl --fail --location --retry 3 "$BASE_URL/$file" --output "$file"
done
for file in "$ENGINE" "$TEMPLATES"; do
  awk -v name="$file" '$2 == name || $2 == "*" name {print}' SHA512-SUMS.txt > "$file.sha512"
  test -s "$file.sha512"
  sha512sum --check "$file.sha512"
done
unzip -o "$ENGINE"
mv "Godot_v${VERSION}-stable_linux.x86_64" godot
chmod +x godot
unzip -o "$TEMPLATES" 'templates/web_*.zip' 'templates/version.txt'
cp templates/web_*.zip templates/version.txt "$TEMPLATE_DIR/"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$INSTALL_DIR" >> "$GITHUB_PATH"
fi
./godot --version
printf 'Godot installed: %s/godot\nWeb templates: %s\n' "$INSTALL_DIR" "$TEMPLATE_DIR"
