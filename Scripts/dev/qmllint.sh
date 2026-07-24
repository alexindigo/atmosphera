#!/usr/bin/env -S bash
set -euo pipefail

# QML Linter Script — runs Qt6 qmllint with Atmosphera import paths.
# When run inside the devcontainer, QS_VFS should point at the
# generated VFS (set by precommit-check.sh). In host-mode (no QS_VFS),
# falls back to repo-relative imports (noisier but backwards compatible).

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
    echo "qmllint version $QMLLINT_VERSION is too old." >&2
    echo "Install Qt 6.6+ qmllint via 'qt6-declarative-tools' or equivalent." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMPORT_OPTS=(-I "$REPO_ROOT" -I /usr/lib/qt6/qml/ -I /usr/lib/qt6/qml/Quickshell/)

if [ -n "${QS_VFS:-}" ] && [ -d "$QS_VFS" ]; then
    IMPORT_OPTS=(-I "$QS_VFS" "${IMPORT_OPTS[@]}")
fi

# Categories enforced as errors, beyond those qmllint exits non-zero for.
# Added progressively as they are fixed across the codebase.
ENFORCED_CATEGORIES=(
    missing-type
    unresolved-alias
    unintentional-empty-block
    read-only-property
    confusing-expression-statement
    alias-cycle
    duplicate-property-binding
    assignment-in-condition
    property-override
    syntax
)

# Collect all .qml files or use provided args
if [ $# -gt 0 ]; then
    mapfile -t all_files < <(find "$@" -name "*.qml" -type f | sort)
else
    mapfile -t all_files < <(find . -name "*.qml" -type f ! -path "./.git/*" ! -path "./Plugins/*" | sort)
fi

[ ${#all_files[@]} -eq 0 ] && { echo "No QML files found"; exit 0; }

echo "Linting ${#all_files[@]} QML files..."
ec=0
output=$("$QMLLINT" "${IMPORT_OPTS[@]}" "${all_files[@]}" 2>&1) || ec=$?

has_errors=0

# Check exit code — qmllint may exit non-zero for hard errors.
[ $ec -ne 0 ] && has_errors=1

# Check explicitly enforced categories (these may not always cause
# non-zero exit from qmllint itself, especially in Qt 6.11).
# Only matches Warning/Error lines to respect .qmllint.ini severity.
for cat in "${ENFORCED_CATEGORIES[@]}"; do
    if grep -E "^(Warning|Error):.*\[$cat\]" <<< "$output" >/dev/null 2>&1; then
        has_errors=1
        break
    fi
done

if [ -n "$output" ]; then
    echo "$output" >&2
fi

if [ $has_errors -eq 1 ]; then
    echo "qmllint: FAILED" >&2
    exit 1
fi

echo "qmllint: clean"
