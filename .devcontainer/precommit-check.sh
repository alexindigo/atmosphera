#!/usr/bin/env bash
set -euo pipefail

# Runs inside the dev container. Called by .githooks/pre-commit via
# .devcontainer/container-run.sh with staged .qml files as arguments.
#
# Order matters: format FIRST, directly on the workspace bind mount, and
# only then let atmo-dev mount the tooling overlay for linting. Mutating
# an overlay's lower tree while it is mounted is not supported by the
# kernel — a mounted tooling overlay is not a safe write-through
# formatting workspace.

STAGED_QML=("$@")
[ ${#STAGED_QML[@]} -eq 0 ] && exit 0

Scripts/dev/qmlfmt.sh "${STAGED_QML[@]}"
exec atmo-dev Scripts/dev/qmllint.sh "${STAGED_QML[@]}"
