#!/usr/bin/env -S bash
set -euo pipefail

# Export upstream commits as patch files and sync the upstream branch.
#
# Usage: get-patches-from-commits.sh [<commit>...]
#
# Default (no args): patches all commits on upstream/main not yet on
#   upstream branch, then offers to fast-forward upstream.
# With explicit commits: patches only those commits (by hash or range).

REPO_ROOT="$(git rev-parse --show-toplevel)"
PATCHES_DIR="$REPO_ROOT/patches"

CREATED=()
mkpatch() {
  while IFS= read -r line; do
    CREATED+=("$line")
  done < <(git format-patch "$@" -o "$PATCHES_DIR")
}

mkdir -p "$PATCHES_DIR"

# Determine what to patch
if [ $# -gt 0 ]; then
  # Explicit commits given — process each individually
  i=1
  for commit in "$@"; do
    if [[ "$commit" == *".."* ]]; then
      mkpatch --start-number="$i" "$commit"
    else
      mkpatch --start-number="$i" -1 "$commit"
    fi
    i=$(find "$PATCHES_DIR" -maxdepth 1 -name '*.patch' | wc -l)
    i=$((i + 1))
  done
else
  # Default: new commits on upstream/main not yet on upstream
  NEW_COMMITS="$(git log --oneline upstream..upstream/main 2>/dev/null || true)"

  if [ -z "$NEW_COMMITS" ]; then
    echo "✅ upstream branch is already in sync with upstream/main."
    echo ""
    echo "Last 10 commits on upstream/main:"
    git log --oneline --date=format-local:"%Y-%m-%d %H:%M:%S" --format="%h %ad %s" -10 upstream/main
    echo ""
    echo "To cherry-pick specific commits:"
    echo "  ./Scripts/dev/get-patches-from-commits.sh <commit1> <commit2>"
    exit 0
  fi

  echo "New commits on upstream/main not yet on upstream branch:"
  echo "$NEW_COMMITS"
  echo ""

  mkpatch "upstream..upstream/main"

  echo ""
  read -p "Fast-forward upstream branch to match upstream/main? [y/N] " -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git branch -f upstream upstream/main
    git push origin upstream
    echo "✅ upstream branch updated and pushed."
  fi
fi

if [ ${#CREATED[@]} -gt 0 ]; then
  echo ""
  echo "Patches created:"
  printf "  %-55s %s\n" "FILE" "COMMIT"
  printf "  %-55s %s\n" "----" "------"
  for f in "${CREATED[@]}"; do
    fname=$(basename "$f")
    commit_info=$(sed -n 's/^From \([a-f0-9]*\) .*$/\1/p' "$f" | head -1)
    if [ -n "$commit_info" ]; then
      printf "  %-55s %s\n" "$fname" "$commit_info"
    else
      printf "  %-55s\n" "$fname"
    fi
  done
  echo ""
  echo "Patches in: $PATCHES_DIR"
  echo "Apply with: ./Scripts/dev/apply-patch.sh <patch-file>"
fi
