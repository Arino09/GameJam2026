#!/usr/bin/env bash
# Run after checkout; source the generated environment in each new shell.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
CLOUD_DIR="$PROJECT_DIR/.godot/cloud"
export GODOT_INSTALL_DIR="$CLOUD_DIR/godot/$GODOT_VERSION"
export XDG_DATA_HOME="$CLOUD_DIR/data"
export XDG_CACHE_HOME="$CLOUD_DIR/cache"
export XDG_CONFIG_HOME="$CLOUD_DIR/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
bash "$PROJECT_DIR/tools/install-godot-ci.sh"
export GODOT_BIN="$GODOT_INSTALL_DIR/godot"
{
  printf 'export GODOT_VERSION=%q\n' "$GODOT_VERSION"
  printf 'export GODOT_BIN=%q\n' "$GODOT_BIN"
  printf 'export XDG_DATA_HOME=%q\n' "$XDG_DATA_HOME"
  printf 'export XDG_CACHE_HOME=%q\n' "$XDG_CACHE_HOME"
  printf 'export XDG_CONFIG_HOME=%q\n' "$XDG_CONFIG_HOME"
  printf 'export PATH=%q:"$PATH"\n' "$GODOT_INSTALL_DIR"
} > "$CLOUD_DIR/env.sh"
printf 'Activate in this shell: source %q\n' "$CLOUD_DIR/env.sh"
