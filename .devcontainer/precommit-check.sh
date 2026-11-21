#!/usr/bin/env bash
set -euo pipefail

# Runs inside the dev container. Called by .githooks/pre-commit via
# .devcontainer/container-run.sh with staged .qml files as arguments.
#
# Format directly on the workspace bind mount. Full QML lint, metadata
# contracts and canaries run in CI, not in the commit's sanity-check path.

STAGED_QML=("$@")
[ ${#STAGED_QML[@]} -eq 0 ] && exit 0

for file in "${STAGED_QML[@]}"; do
  Scripts/dev/qmlfmt.sh "$file"
done
