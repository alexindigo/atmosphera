#!/bin/bash
# install_scripts.sh — install the atmosphera CLI dispatcher to a bin directory
set -euo pipefail

BIN_DIR="${1:-$HOME/.local/bin}"

if [ ! -d "$BIN_DIR" ]; then
  echo "Creating $BIN_DIR..." >&2
  mkdir -p "$BIN_DIR"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/Scripts/bash"

# Install the dispatcher (the only binary needed on PATH)
src="$SCRIPT_DIR/atmosphera"
target="$BIN_DIR/atmosphera"

if [ ! -f "$src" ] || [ ! -x "$src" ]; then
  echo "Error: dispatcher not found at $src" >&2
  exit 1
fi

ln -sf "$src" "$target"
echo "  $target -> $src"
echo "Installed atmosphera dispatcher to $BIN_DIR"
