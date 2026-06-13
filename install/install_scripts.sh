#!/bin/bash
set -euo pipefail

BIN_DIR="${1:-$HOME/.local/bin}"

if [ ! -d "$BIN_DIR" ]; then
  echo "Creating $BIN_DIR..." >&2
  mkdir -p "$BIN_DIR"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/Scripts/bash"

installed=0
for script in "$SCRIPT_DIR"/atmosphera-*; do
  [ -f "$script" ] && [ -x "$script" ] || continue
  name=$(basename "$script")
  target="$BIN_DIR/$name"
  ln -sf "$script" "$target"
  echo "  $target -> $script"
  installed=$((installed + 1))
done

echo "Installed $installed scripts to $BIN_DIR"
