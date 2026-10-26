# Dev VM package

Load the VM access skill and use the task's assigned VM and disk-backed
workspace. Keep all builds, installation checks and runtime tests in that guest.

`aur/PKGBUILD` is a local-checkout adapter for the repo-owned AUR recipe. It
sources `packaging/aur/atmosphera-git/PKGBUILD`, including its shared dependencies,
package function and version calculation. Its install hook links to the same
canonical hook. There is no second dependency list or installed file list to
keep in sync. See [AUR packaging](../../DEVELOPMENT.md#aur-packaging).

Deliver the repository layout to the guest, rather than copying the adapter
alone. In the assigned VM, keep outputs in a separate disk-backed build directory:

```bash
# Set these to the task's guest checkout and disk-backed build directory first.
: "${CHECKOUT:?guest checkout required}" "${BUILD:?guest build directory required}"
mkdir -p "$BUILD/tmp"
export TMPDIR="$BUILD/tmp"
export ATMOSPHERA_CHECKOUT="$CHECKOUT" ATMOSPHERA_REF="${ATMOSPHERA_REF:-main}"
export BUILDDIR="$BUILD" PKGDEST="$BUILD" SRCDEST="$BUILD"
cd "$CHECKOUT/dev/vm/aur"
makepkg -s --noconfirm
```

`ATMOSPHERA_CHECKOUT` defaults to `/mnt/hostshare`; `ATMOSPHERA_REF` defaults to
`main`. Git sources build **committed state**. Use the task branch as the ref
when testing unpublished commits. Install the resulting package with `pacman -U`
in the assigned guest when the task calls for an install test; follow that VM's
shell lifecycle procedure for runtime checks.
