#!/usr/bin/env -S bash
set -euo pipefail

# Shell version switcher.
# Kills current shell and launches a different one — windows stay open.

QS_BIN="qs"

declare -A SHELLS
SHELLS["atmosphera"]="/etc/xdg/quickshell/atmosphera"

list() {
  echo "Available shells:"
  for name in "${!SHELLS[@]}"; do
    printf "  %-20s %s\n" "$name" "${SHELLS[$name]}"
  done
  echo ""
  echo "Any directory path also works: launch ~/path/to/shell"
}

launch() {
  local target="${1:-}"
  [ -z "$target" ] && { echo "Usage: $0 launch <name|path>" >&2; list; exit 1; }

  # If it's a known name, resolve to path; otherwise treat as a direct path
  if [ -n "${SHELLS[$target]:-}" ]; then
    target="${SHELLS[$target]}"
  elif [ ! -d "$target" ]; then
    echo "Unknown shell and not a valid directory: $target" >&2
    list
    exit 1
  fi

  echo "Launching: $target"
  "$QS_BIN" kill -p "$target" 2>/dev/null || true
  sleep 0.3
  exec "$QS_BIN" -p "$target" -d
}

stop() {
  local killed=false
  for path in "${SHELLS[@]}"; do
    if "$QS_BIN" kill -p "$path" 2>/dev/null; then
      killed=true
    fi
  done
  $killed && echo "Shell stopped." || echo "No shell running (known locations)."
}

case "${1:-}" in
  list) list ;;
  launch) launch "${2:-}" ;;
  stop) stop ;;
  *) echo "Usage: $0 list|launch <name|path>|stop" >&2; list; exit 1 ;;
esac
