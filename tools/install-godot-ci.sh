#!/usr/bin/env bash
# Linux CI installation from official Godot releases, verified with SHA-512.
set -euo pipefail
VERSION="${GODOT_VERSION:-4.7.2}"
INSTALL_DIR="${RUNNER_TEMP:?This installer is intended for GitHub Actions}/godot"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/$VERSION.stable"
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
echo "$INSTALL_DIR" >> "$GITHUB_PATH"
./godot --version
