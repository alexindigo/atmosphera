#!/usr/bin/env bash
# Host side is Git plumbing only; the checker executes in the normal container.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_DIR="$(git rev-parse --absolute-git-dir)"
INDEX_TREE="$(git write-tree)" # fails closed for an unmerged index

# Archive cannot preserve the identity of symlink/submodule plugin inputs.
while IFS= read -r -d '' entry; do
  case "$entry" in
    '120000 '*|'160000 '*)
      echo "plugin lint: symlink/submodule input is unsupported: ${entry#*$'\t'}" >&2
      exit 1
      ;;
  esac
done < <(git ls-tree -r -z "$INDEX_TREE" -- builtin/plugins)

[ -d "$GIT_DIR" ] || exit 1
SNAPSHOT="$(mktemp -d "$GIT_DIR/plugin-lint.XXXXXXXX")"
trap 'rm -rf -- "$SNAPSHOT"' EXIT
mkdir -p "$SNAPSHOT/index/builtin/plugins" "$SNAPSHOT/base/builtin/plugins"

archive_plugins() {
  local tree="$1" destination="$2"
  if [ -n "$(git ls-tree "$tree" -- builtin/plugins)" ]; then
    git archive --format=tar "$tree" -- builtin/plugins > "$SNAPSHOT/tree.tar"
    tar -xf "$SNAPSHOT/tree.tar" -C "$destination"
  fi
}

archive_plugins "$INDEX_TREE" "$SNAPSHOT/index"
if BASE_TREE="$(git rev-parse --verify "${PLUGIN_LINT_BASE:-HEAD}^{tree}" 2>/dev/null)"; then
  archive_plugins "$BASE_TREE" "$SNAPSHOT/base"
fi

ATMOSPHERA_PLUGIN_SNAPSHOT_DIR="$SNAPSHOT" \
  "$REPO_ROOT/.devcontainer/container-run.sh" \
  python3 -B Scripts/dev/plugin-lint.py \
  --root /atmosphera-plugin-snapshot/index/builtin/plugins \
  --base-root /atmosphera-plugin-snapshot/base/builtin/plugins \
  --catalog /atmosphera-plugin-snapshot/index/builtin/plugins/registry.json
