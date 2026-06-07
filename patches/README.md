# Upstream Patches

Patch files for cherry-picking upstream (Noctalia Shell) fixes into Atmosphera.

## Workflow

### 1. Generate patches for new upstream commits

```bash
./Scripts/dev/get-patches-from-commits.sh
```

This finds all commits on `upstream/main` not yet on the `upstream` branch,
exports them as `.patch` files here, and asks if you want to fast-forward the
`upstream` branch.

You can also generate patches for specific commits:

```bash
./Scripts/dev/get-patches-from-commits.sh <commit1> <commit2> <commit3>
./Scripts/dev/get-patches-from-commits.sh <from>..<to>
```

> **NOTE:** Patches are numbered oldest → newest in the order you pass them.

### 2. Pull a specific commit (e.g. from v5-dev)

```bash
curl -Lo patches/<name>.patch https://github.com/noctalia-dev/noctalia-shell/commit/<hash>.patch
```

Saves the patch directly into `patches/`, ready to apply with step 3.

### 3. Apply a patch

```bash
./Scripts/dev/apply-patch.sh patches/<patch-file>.patch
```

This shows a summary, asks for confirmation, applies via `git am`, then offers
to delete the patch file after a successful apply.

## Notes

- Patch files (`*.patch`) are gitignored at the repo root.
- After applying and pushing, sync the `upstream` branch with:
  `git push origin upstream`
- You can also manually edit a patch file before applying if the automatic
  `--reject` fallback leaves unresolved hunks.
