#!/usr/bin/env bash
set -euo pipefail

# Runs inside devcontainer. Called by .githooks/pre-commit with staged .qml files.
# Marshals which Scripts/dev/* checks run in pre-commit context.

STAGED_QML=("$@")
[ ${#STAGED_QML[@]} -eq 0 ] && exit 0

Scripts/dev/qmlfmt.sh "${STAGED_QML[@]}"
Scripts/dev/qmllint.sh "${STAGED_QML[@]}"
