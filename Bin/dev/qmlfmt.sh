#!/usr/bin/env -S bash
set -euo pipefail

# QML Formatter Script

# Find qmlformat binary
if command -v qmlformat &>/dev/null; then
    QMLFORMAT="qmlformat"
elif [ -x "/usr/lib/qt6/bin/qmlformat" ]; then
    QMLFORMAT="/usr/lib/qt6/bin/qmlformat"
elif [ -x "/usr/lib/qt5/bin/qmlformat" ]; then
    QMLFORMAT="/usr/lib/qt5/bin/qmlformat"
else
    echo "No 'qmlformat' found in PATH or /usr/lib/qt6/bin." >&2
    echo "Install it via 'qt6-declarative-tools' or 'qt5-declarative' (depending on your distro) to proceed." >&2
    exit 1
fi

echo "Using 'qmlformat' for formatting: $QMLFORMAT"
export QMLFORMAT
format_file() { "$QMLFORMAT" -w 2 -W 360 -S --semicolon-rule always -i "$1" || { echo "Failed: $1" >&2; return 1; }; }

export -f format_file

# Find all .qml files
mapfile -t all_files < <(find "${1:-.}" -name "*.qml" -type f)
[ ${#all_files[@]} -eq 0 ] && { echo "No QML files found"; exit 0; }

echo "Formatting ${#all_files[@]} files..."
printf '%s\0' "${all_files[@]}" | \
    xargs -0 -P "${QMLFMT_JOBS:-$(nproc)}" -I {} bash -c 'format_file "$@"' _ {} \
    && echo "Done" || { echo "Errors occurred" >&2; exit 1; }