#!/usr/bin/env bash
# Lint an external plugins repository with the shell-owned checker, inside the
# shell's dev container. Host side is Git plumbing only; the checker executes in
# the normal container against private index/base snapshots.
#
# Usage: plugin-lint-repo.sh <plugins-repo> [<base-rev>]
#   <base-rev> defaults to HEAD; the base is empty if the repo has no commits.
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: plugin-lint-repo.sh <plugins-repo> [<base-rev>]" >&2
  exit 2
fi

SHELL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

engine_available() {
  if [ -n "${ATMOSPHERA_CONTAINER_ENGINE:-}" ]; then
    command -v "$ATMOSPHERA_CONTAINER_ENGINE" >/dev/null 2>&1
  else
    command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1
  fi
}
engine_available || {
  echo "plugin lint: no container engine; install podman or docker, or set ATMOSPHERA_CONTAINER_ENGINE=podman|docker" >&2
  exit 1
}

REPO="$(git -C "$1" rev-parse --show-toplevel)"
BASE_REV="${2:-HEAD}"
INDEX_TREE="$(git -C "$REPO" write-tree)" # fails closed for an unmerged index

# Archive cannot preserve the identity of symlink/submodule plugin inputs.
while IFS= read -r -d '' entry; do
  case "$entry" in
    '120000 '*|'160000 '*)
      echo "plugin lint: symlink/submodule input is unsupported: ${entry#*$'\t'}" >&2
      exit 1
      ;;
  esac
done < <(git -C "$REPO" ls-tree -r -z "$INDEX_TREE")

GIT_DIR="$(git -C "$SHELL_ROOT" rev-parse --absolute-git-dir)"
SNAPSHOT="$(mktemp -d "$GIT_DIR/plugin-lint.XXXXXXXX")"
trap 'rm -rf -- "$SNAPSHOT"' EXIT
mkdir -p "$SNAPSHOT/index" "$SNAPSHOT/base"

git -C "$REPO" archive --format=tar "$INDEX_TREE" | tar -xf - -C "$SNAPSHOT/index"
if [ "$BASE_REV" = HEAD ] && ! git -C "$REPO" rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null; then
  : # repository without commits: empty base
else
  git -C "$REPO" archive --format=tar "$BASE_REV" | tar -xf - -C "$SNAPSHOT/base"
fi

ATMOSPHERA_PLUGIN_SNAPSHOT_DIR="$SNAPSHOT" \
  "$SHELL_ROOT/.devcontainer/container-run.sh" sh -c '
    set -eu
    if [ -f /atmosphera-plugin-snapshot/index/.github/scripts/validate-registry.py ]; then
      python3 -B /atmosphera-plugin-snapshot/index/.github/scripts/validate-registry.py
    fi
    python3 -B Scripts/dev/plugin-lint.py --root /atmosphera-plugin-snapshot/index --base-root /atmosphera-plugin-snapshot/base
    python3 -B Scripts/dev/plugin-lint.py --root /atmosphera-plugin-snapshot/index
  '
