#!/usr/bin/env bash
# Host-side Git plumbing/copy only, following plugin-lint-staged.sh. All analysis
# runs inside the normal check container; worktree Git internals stay on the host.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_DIR="$(git rev-parse --absolute-git-dir)"
INDEX_TREE="$(git write-tree)"
if [ -n "$(git ls-tree -r --name-only "$INDEX_TREE" -- .envrc '*/.envrc')" ]; then
  echo "settings gate: refusing to export a tracked environment file" >&2
  exit 1
fi
SNAPSHOT="$(mktemp -d "$GIT_DIR/settings-lint.XXXXXXXX")"
trap 'rm -rf -- "$SNAPSHOT"' EXIT
mkdir "$SNAPSHOT/index"
git archive --format=tar "$INDEX_TREE" > "$SNAPSHOT/tree.tar"
tar -xf "$SNAPSHOT/tree.tar" -C "$SNAPSHOT/index"
ATMOSPHERA_SETTINGS_SNAPSHOT_DIR="$SNAPSHOT" \
  "$REPO_ROOT/.devcontainer/container-run.sh" \
  python3 -B /atmosphera-settings-snapshot/index/Scripts/dev/settings-contract-check.py
