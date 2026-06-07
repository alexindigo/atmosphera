#!/usr/bin/env -S bash
set -euo pipefail

# Interactively review and apply an upstream patch
#
# Usage: apply-patch.sh [-y] [-r] [-d] <patch-file>
#
# Options:
#   -y    Skip confirmation prompt (auto-yes, auto-stash)
#   -r    Auto-yes to --reject fallback when git am fails
#   -d    Delete patch file after successful apply
#
# Steps:
#   1. Shows patch summary
#   2. Asks to apply (unless -y)
#   3. Stashes any uncommitted changes (unless declined)
#   4. Applies with git am (preserves author + message)
#   5. If am fails, offers --reject (auto-yes if -r)
#   6. Restores stashed changes (if any)
#   7. Asks to delete patch file (unless -d)

AUTO_APPLY=false
AUTO_REJECT=false
AUTO_DELETE=false

while getopts ":dry" opt; do
  case $opt in
    d) AUTO_DELETE=true ;;
    r) AUTO_REJECT=true ;;
    y) AUTO_APPLY=true ;;
    *) echo "Usage: $0 [-y] [-r] [-d] <patch-file>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

PATCH_FILE="${1:?Usage: $0 [-y] [-r] [-d] <patch-file>}"

if [ ! -f "$PATCH_FILE" ]; then
  echo "❌ Patch file not found: $PATCH_FILE"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════╗"
echo "║        Upstream Patch Review         ║"
echo "╚══════════════════════════════════════╝"
echo ""

echo "Subject: $(head -1 "$PATCH_FILE" | sed 's/^From //' || true)"
grep -m1 "^Date:" "$PATCH_FILE" || true
grep -m1 "^From:" "$PATCH_FILE" || true
echo ""

echo "Files changed:"
git apply --stat "$PATCH_FILE" 2>/dev/null || echo "  (could not parse)"
echo ""

echo "Full diff:"
cat "$PATCH_FILE"
echo ""

if ! $AUTO_APPLY; then
  read -p "Apply this patch? [y/N] " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipped."
    exit 0
  fi
fi

STASHED=false
if ! git diff --quiet --exit-code 2>/dev/null || ! git diff --cached --quiet --exit-code 2>/dev/null; then
  if $AUTO_APPLY; then
    STASHED=true
    echo "📦 Stashing uncommitted changes..."
    git stash push -m "apply-patch: temporary stash" >/dev/null 2>&1
  else
    echo ""
    read -p "Uncommitted changes detected. Stash them? [Y/n] " -r
    if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
      STASHED=true
      echo "📦 Stashing uncommitted changes..."
      git stash push -m "apply-patch: temporary stash" >/dev/null 2>&1
    else
      echo "Aborting — cannot apply with uncommitted changes."
      exit 1
    fi
  fi
fi

cleanup() {
  if $STASHED; then
    git stash pop >/dev/null 2>&1 || true
    echo "📦 Restored stashed changes."
  fi
}
trap cleanup EXIT

echo ""
echo "Applying..."

if [ -d ".git/rebase-apply" ]; then
  echo "⚠️  Stale git am state detected. Cleaning up..."
  git am --abort 2>/dev/null || rm -rf ".git/rebase-apply"
fi

APPLIED=false

if git am "$PATCH_FILE" 2>&1; then
  APPLIED=true
else
  git am --abort 2>/dev/null || true
  echo ""
  echo "⚠️  git am failed — patch does not apply cleanly."
  echo ""

  conflict_file=$(git apply --check "$PATCH_FILE" 2>&1 | grep "^error:" | head -3 || true)
  if [ -n "$conflict_file" ]; then
    echo "Problem files:"
    echo "$conflict_file" | sed 's/^error: //' | while IFS= read -r line; do
      echo "  • $line"
    done
    echo ""
  fi

  DO_REJECT=$AUTO_REJECT
  if ! $DO_REJECT; then
    echo ""
    read -p "Apply with --reject? [y/N] " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      DO_REJECT=true
    fi
  fi
  if $DO_REJECT; then
    echo ""
    echo "Applying with --reject..."
    reject_output=$(git apply --reject "$PATCH_FILE" 2>&1) || true

    rej_files=()
    while IFS= read -r -d '' f; do
      rej_files+=("$f")
    done < <(find . -name '*.rej' 2>/dev/null)

    missing_files=$(echo "$reject_output" | grep "No such file or directory" | sed 's/^error: //; s/: No such file or directory//' | head -3 || true)

    if [ ${#rej_files[@]} -gt 0 ] || [ -n "$missing_files" ]; then
      echo ""
      echo "⚠️  Patch applied partially."
      if [ ${#rej_files[@]} -gt 0 ]; then
        echo ""
        echo "Rejected hunks (resolve manually):"
        for f in "${rej_files[@]}"; do
          echo "  • $f"
        done
      fi
      if [ -n "$missing_files" ]; then
        echo ""
        echo "Files that don't exist in our fork (skipped):"
        echo "$missing_files" | while IFS= read -r line; do
          echo "  • $line"
        done
      fi
      echo ""
      echo "To commit: resolve .rej files, then:"
      echo "    git add -A"
      echo "    git commit -m \"$(head -1 "$PATCH_FILE" | sed 's/^From [^ ]* //' || true)\""
      APPLIED=true
    else
      echo ""
      echo "✅ Patch applied with --reject (no rejects)."
      APPLIED=true
    fi
  else
    exit 1
  fi
fi

if $APPLIED; then
  echo ""
  echo "✅ Patch applied successfully."
  if $AUTO_DELETE; then
    rm "$PATCH_FILE"
    echo "✅ Patch file deleted."
  else
    read -p "Delete patch file? [y/N] " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm "$PATCH_FILE"
      echo "✅ Patch file deleted."
    fi
  fi
fi
