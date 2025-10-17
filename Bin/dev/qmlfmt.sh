#!/usr/bin/env -S bash
set -euo pipefail

# QML Formatter Script
# Uses: https://github.com/jesperhh/qmlfmt
# Install: AUR package "qmlfmt-git" (requires qt6-5compat)

command -v qmlfmt &>/dev/null || { echo "qmlfmt not found" >&2; exit 1; }

format_file() { qmlfmt -e -b 360 -t 2 -i 2 -w "$1" || { echo "Failed: $1" >&2; return 1; }; }
export -f format_file

mapfile -t files < <(find "${1:-.}" -name "*.qml" -type f)
[ ${#files[@]} -eq 0 ] && { echo "No QML files found"; exit 0; }

echo "Formatting ${#files[@]} files..."
printf '%s\0' "${files[@]}" | \
    xargs -0 -P "${QMLFMT_JOBS:-$(nproc)}" -I {} bash -c 'format_file "$@"' _ {} \
    && echo "Done" || { echo "Errors occurred" >&2; exit 1; }