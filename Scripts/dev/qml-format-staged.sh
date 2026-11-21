#!/usr/bin/env bash
# Shared by the tracked hook and optional Lefthook, regardless of its shell.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

mapfile -d '' -t files < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.qml')
[ "${#files[@]}" -gt 0 ] || exit 0

# Drain container output before returning to Git; only show failures.
hook_output=$("$REPO_ROOT/.devcontainer/container-run.sh" --plain \
  .devcontainer/precommit-check.sh "${files[@]}" 2>&1) && hook_ec=0 || hook_ec=$?
if [ "$hook_ec" -ne 0 ]; then
  echo "$hook_output" >&2
  exit 1
fi

# Never refresh unrelated partially staged files from their working-tree copy.
git add -- "${files[@]}"
