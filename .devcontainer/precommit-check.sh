#!/usr/bin/env bash
set -euo pipefail

# Runs inside devcontainer via atmo-dev. Called by .githooks/pre-commit
# with staged .qml files. atmo-dev has already set up overlay + VFS + env.
# This script only cares about formatting and linting the staged files.

STAGED_QML=("$@")
[ ${#STAGED_QML[@]} -eq 0 ] && exit 0

Scripts/dev/qmlfmt.sh "${STAGED_QML[@]}"
Scripts/dev/qmllint.sh "${STAGED_QML[@]}"
