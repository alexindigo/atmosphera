#!/usr/bin/env -S bash
set -euo pipefail

# QML Linter Script — runs Qt6 qmllint with Atmosphera import paths.

export QT_LOGGING_RULES="qt.qmldom.*=false"

# Find qmllint binary
QMLLINT=""
for path in "/usr/lib64/qt6/bin/qmllint" "/usr/lib/qt6/bin/qmllint"; do
    if [ -x "$path" ]; then
        QMLLINT="$path"
        break
    fi
done

if [ -z "$QMLLINT" ] && command -v qmllint &>/dev/null; then
    QMLLINT="qmllint"
fi

if [ -z "$QMLLINT" ]; then
    echo "No 'qmllint' found in standard locations or PATH." >&2
    echo "Install via 'qt6-declarative-tools' or equivalent." >&2
    exit 1
fi

QMLLINT_VERSION=$("$QMLLINT" --version 2>&1 || echo "unknown")
if [[ ! "$QMLLINT_VERSION" =~ ^qmllint\ [6-9]\. ]]; then
    echo "Warning: qmllint version $QMLLINT_VERSION may not support full error detection." >&2
    echo "Install Qt6 qmllint via 'qt6-declarative-tools'." >&2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMPORT_OPTS=(-I "$REPO_ROOT" -I /usr/lib/qt6/qml/ -I /usr/lib/qt6/qml/Quickshell/)
ERROR_COUNT=0

lint_file() {
    local file=$1
    local output
    output=$("$QMLLINT" "${IMPORT_OPTS[@]}" "$file" 2>&1) || true
    local has_errors=0
    # Check for error-severity warnings (they produce non-zero exit)
    # Also check for explicit error/warning markers
    if echo "$output" | grep -q 'Error:\|error\]'; then
        has_errors=1
    fi
    if [ -n "$output" ]; then
        if [ $has_errors -eq 1 ]; then
            echo "$output" >&2
            return 1
        else
            # Info/warning only — print but don't fail
            echo "$output" >&2
        fi
    fi
    return 0
}

export -f lint_file
export QMLLINT IMPORT_OPTS

# Collect all .qml files or use provided args
if [ $# -gt 0 ]; then
    mapfile -t all_files < <(find "$@" -name "*.qml" -type f | sort)
else
    mapfile -t all_files < <(find . -name "*.qml" -type f ! -path "./.git/*" ! -path "./Plugins/*" | sort)
fi

[ ${#all_files[@]} -eq 0 ] && { echo "No QML files found"; exit 0; }

echo "Linting ${#all_files[@]} QML files..."
for f in "${all_files[@]}"; do
    if ! lint_file "$f"; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
done

if [ $ERROR_COUNT -gt 0 ]; then
    echo "qmllint: $ERROR_COUNT file(s) with errors" >&2
    exit 1
fi

echo "qmllint: clean"
