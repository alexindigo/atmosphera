# Atmosphera — Development

## Release identity

The tracked root `VERSION` is the authoritative release/API version. Update it
alongside the release's changelog commit, **before** tagging, and tag that commit
with the same version (for example, `VERSION` contains `0.8.0` and the tag is
`v0.8.0`). Ordinary development commits retain that version and must remain
API-compatible until it is explicitly changed.

`Services/Version.qml` reads the supplied file in source archives and installed
trees. A checkout rooted at the shell directory appends `-g<HEAD hash>` for
display/diagnostics; Git tags and commit counts do not choose or increment the
release version. Compatibility and changelog identities use only the release
part. Package-written build identities such as `0.8.0.r12.gabc1234` (including
pkgrel suffixes) remain supported; they are not bumped API versions.

## AUR packaging

Edit AUR recipes in **this repository**, under `packaging/aur/`, rather than in
the AUR clones. `metadata.sh` owns dependencies/optional dependencies/provides;
`package.sh` owns the installed file set for stable, -git and the VM dev package.
The two `PKGBUILD` entry points own only variant-specific metadata and sources.
Install hooks live alongside them. The publisher inlines the shared fragments
so AUR receives standalone PKGBUILDs with no dependency on the repo layout.

On a `vMAJOR.MINOR.PATCH` tag, `update-aur-package.yml` checks out that tag's
recipes, fills the stable version/pkgrel (1), refreshes its archive checksum and
`.SRCINFO`, and publishes both AUR packages with the existing AUR key. The -git
recipe retains AUR's current pkgver/pkgrel when comparing; recipe or install-hook
changes bump its pkgrel once, while unchanged recipes are skipped. Manual runs
require an explicit release tag. Both recipes are prepared before either is
pushed. Publication mode builds both recipes in private directories and commits
all changed recipes before pushing either. Build checks use `makepkg --nodeps`
because this QML/data package needs no dependency bootstrap to validate its
archive; generated VCS build versions never rewrite publication counters.
A remote failure fails the job, and an always-run summary records each repo's
local gate and publication status. AUR has no cross-repository atomic push.
Rerunning the same release against fresh clones skips an already-published
stable recipe and publishes only missing changes; identical -git recipes do not
bump pkgrel again. Reusing clean clones with an unpublished local commit is also
supported: that commit is pushed rather than regenerated.

Publication policy is loaded from the repository's maintained default branch;
only recipe data comes from the selected tag. Replaying a tag does not execute
its older publisher. Before either recipe is modified, pacman's `vercmp` checks
the requested stable identity (`tag version`, pkgrel 1) against both the clean
local commit and, in publication mode, fetched upstream `.SRCINFO`. An older
version, epoch or same-version higher published pkgrel is rejected for both
repositories. Equal full identities keep the idempotent retry behavior above.
Generated -git versions are preserved, not compared as stable release versions.

All release runs share one serialized concurrency group with `queue: max`:
GitHub retains up to 100 pending runs instead of replacing the pending release.
The platform cancels additional runs when that queue is full; inspect canceled
runs and replay the intended tag via workflow dispatch after capacity returns.
Waiting order is not guaranteed to match version order, so the version guard
also applies to queued runs. A VM lint/test validates the configuration and
publisher, not GitHub's live scheduler. Historical workflow definitions remain
historical; these protections apply to runs using the updated workflow.

Publication uses separate privilege domains. Root owns the AUR transport key
and protected Git clones; `--push` requires an explicit keyless `--build-user`
and that account's disk-backed `--worker-root`. All tag-derived recipe evaluation,
checksum updates, metadata generation and build/archive checks run under that
UID with a scrubbed environment, cleared capabilities/groups and no-new-privileges.
Only bounded contents of the three recipe files cross back over JSON; the
publisher never adopts a builder's Git configuration, hooks or file paths.
Both preparations/builds complete before publisher commits, and both commits
complete before authenticated pushes. Initial workflow reads use public HTTPS.
The workflow removes its root-owned mode-600 key when the publication step exits.

Every publisher subprocess has a finite deadline: local/metadata commands 30 s,
network/checksum commands 180 s, builds 600 s, and pushes 180 s by default.
Workers have an enclosing finite budget derived from those limits. The positive
finite CLI timeout options allow explicit task-specific sizing; `--push-timeout`
can bound a stalled receive independently of build time. Timeout tears down only
the invocation's owned process group and reports through the normal summary;
a timed-out push remains remote-state-unconfirmed, never presumed unpublished.

The maintained `packaging/aur/aur-known-hosts` file pins AUR's Ed25519 server
identity against the fingerprints published at https://aur.archlinux.org/;
its comment records the source URL and UTC check date. The workflow installs
that trust file, never unchecked ssh-keyscan output, and forces strict checking
against only that file/algorithm. Publication validates `--known-hosts` against
the maintained pin before fetch/preparation/push; mismatches explain the failed
job summary. Review a fingerprint rotation against AUR's official page before
changing the committed trust entry.

Subprocess errors identify the step and exit status or deadline with a bounded
stderr tail (ordinary commands: 12 lines / 1 KiB; outer workers: 16 lines / 2 KiB
to retain nested failure reasons). Full argv, stdout protocol data and embedded
worker source are never formatted into those errors. The same bounded reason
is included in the per-repository job summary; push uncertainty is preserved.

For preparation without commits or pushes, run inside an Arch test VM with
`pacman-contrib` and `base-devel`, using **clean scratch clones** of both AUR repos:

```sh
python packaging/aur/sync.py v0.9.0 /path/to/scratch/atmosphera /path/to/scratch/atmosphera-git
```

The VM adapter `dev/vm/aur/PKGBUILD` sources the same -git recipe and overrides
only the source URL. `ATMOSPHERA_CHECKOUT` defaults to `/mnt/hostshare`;
`ATMOSPHERA_REF` defaults to `main`. It builds committed state from that local
checkout. Its install hook is a symlink to the canonical hook. Keep the repo
layout intact and run `makepkg` in `dev/vm/aur/`; use `BUILDDIR` and `PKGDEST`
to put build outputs elsewhere on the guest's disk. Do not copy the adapter alone.

## Devcontainer

A devcontainer is provided at `.devcontainer/` for consistent development tooling.
It uses an Arch Linux base and includes Qt6 declarative tools (qmllint, qmlformat,
qmlls), Python, shellcheck, shfmt, and tree-sitter.

Both **rootless Podman** and **Docker** (daemon) are supported, from one image
definition (`.devcontainer/Dockerfile`) and one tooling launcher
(`.devcontainer/container-run.sh`). Other arrangements — rootless Docker,
userns-remap, non-Linux hosts — are not verified configurations; the launcher
stops with an explicit error rather than guessing at identity or security
assumptions.

### Engine selection

The launcher selects the engine in this order:

1. `ATMOSPHERA_CONTAINER_ENGINE=podman|docker` (explicit override)
2. `podman`, if installed
3. `docker`, if installed

A `docker` executable backed by `podman-docker` is recognized as Podman and
receives Podman options. Once selected, an engine failure is a failure — the
launcher never silently retries with the other engine. Selection diagnostics
(requested executable, actual backend) are printed to stderr.

### Images

The launcher builds a local image tagged `localhost/atmosphera-dev:<fingerprint>`,
where the fingerprint covers the Dockerfile, the copied `atmo-dev` wrapper, and
the image's dev-account IDs. Editing those inputs yields a new tag on the next
run; old images are left alone. Build and run always use the same selected
engine.

- **Podman (rootless):** the image keeps the default `dev` account
  (UID/GID 1000); the launcher maps you onto it with
  `--userns=keep-id:uid=1000,gid=1000`, so files written to the workspace are
  owned by you on the host.
- **Docker:** the image is built with your UID/GID (build args `DEV_UID` /
  `DEV_GID`) and the container runs as the named `dev` account — never a
  numeric anonymous user — with the same host-ownership result.

**Rootless Podman prerequisites:** subordinate UID/GID ranges (`/etc/subuid`,
`/etc/subgid`), cgroup v2 with delegated cpu/memory/pids controllers, and a
kernel >= 6.6 (tmpfs `user.*` xattrs, required by the tooling overlay in user
namespace mode). The tooling never uses privileged mode, `:U` volume
relabelling, host socket binds, or host home mounts.

### Running checks by hand

```
# format + lint (what the pre-commit hook runs)
.devcontainer/container-run.sh .devcontainer/precommit-check.sh <files.qml...>

# lint only, read-only overlay + VFS wrapper
.devcontainer/container-run.sh atmo-dev Scripts/dev/qmllint.sh <files.qml...>
```

`precommit-check.sh` formats first, directly on the workspace bind mount, and
only then lets `atmo-dev` mount its tooling overlay for linting. Do not format
through `atmo-dev`: a mounted tooling overlay is not a safe write-through
formatting workspace (mutating a mounted overlay's lower tree is unsupported
by the kernel).

Every run carries resource limits: `--memory=12g --memory-swap=12g
--pids-limit=2048 --cpus=12`. Accepted flags are not proof of enforcement —
verify inside a running container:

```
cat /sys/fs/cgroup/memory.max       # 12884901888
cat /sys/fs/cgroup/memory.swap.max  # 0
cat /sys/fs/cgroup/pids.max         # 2048
cat /sys/fs/cgroup/cpu.max          # 1200000 100000
```

### Editors

- **VSCode (Docker)** — auto-detects `.devcontainer/` and prompts to "Reopen in
  Container". The default profile is Docker-compatible.
- **VSCode (Podman)** — select the "Atmosphera Dev (Podman)" configuration
  (`.devcontainer/podman/`) and set `dev.containers.dockerPath` to `podman` in
  your own user settings. The repository does not edit host-global editor
  settings, and VS Code's Podman support is via its CLI compatibility, not an
  official guarantee.
- **JetBrains** — Dev Containers plugin (JetBrains Toolbox → Plugins).
- **CLI** — the Dev Containers CLI drives either profile (engine selection via
  `--docker-path`, profile selection via `--config` — two separate actions):

  ```
  # Docker (default profile)
  devcontainer build --docker-path docker --workspace-folder . \
    --config .devcontainer/devcontainer.json
  devcontainer up --docker-path docker --workspace-folder . \
    --config .devcontainer/devcontainer.json
  devcontainer exec --docker-path docker --workspace-folder . \
    --config .devcontainer/devcontainer.json \
    .devcontainer/precommit-check.sh <file.qml>

  # Podman (alternate profile; --buildkit never on build/up)
  devcontainer build --docker-path podman --buildkit never --workspace-folder . \
    --config .devcontainer/podman/devcontainer.json
  devcontainer up --docker-path podman --buildkit never --workspace-folder . \
    --config .devcontainer/podman/devcontainer.json \
    --include-configuration --include-merged-configuration
  devcontainer exec --docker-path podman --workspace-folder . \
    --config .devcontainer/podman/devcontainer.json \
    .devcontainer/precommit-check.sh <file.qml>
  ```

**What runs in the container:** linting, formatting, and non-Wayland tooling,
including headless Quickshell VFS generation for import resolution.

**What never runs in the container or on your host session:** the QuickShell
runtime (`qs`, `atmosphera-session`) and cold-load smoke tests — those drive a
real shell and belong in a throwaway VM (see below).

## QML Linting

```
Scripts/dev/qmllint.sh [path ...]
```

Uses Qt6's qmllint with severity levels configured in `.qmllint.ini`.

**With devcontainer:** recommended — tools are pre-installed. Run via
`.devcontainer/container-run.sh` (above), or in a devcontainer editor terminal.

**Without devcontainer:**
- Nix: `nix develop` — provides the same tools via the flake
- Host: install `qt6-declarative` on Arch, or `qt6-declarative-dev-tools` /
  `qt6-tools-dev-tools` on Ubuntu/Debian (requires Qt 6.6+)

## QML Formatting

```
Scripts/dev/qmlfmt.sh [path ...]
```

Uses `qmlformat` with 2-space indent and 360-character line width. Same
devcontainer / Nix / host options as linting above.

## Pre-commit Hook

A tracked pre-commit hook lives at `.githooks/pre-commit`. It runs qmlformat
and qmllint on staged QML files inside the dev container (engine selected as
above), blocking commits with errors, and rebuilds the settings search index
when its inputs change.

Staged `builtin/plugins/` changes also run the shell-owned plugin compatibility
checker through the same container launcher. The host performs Git plumbing
only: it archives index and `HEAD` plugin snapshots under the clone/worktree's
Git directory. The launcher mounts those private snapshots read-only, including
when a linked worktree's Git directory is outside its workspace. The checker
runs after formatting/restaging, so it validates the final index that will be
committed. Unmerged indexes and symlink/submodule plugin inputs are rejected.
Code/assets/manifest changes need a higher plugin version; documentation-only
changes do not. Catalog/manifest agreement is always checked. External plugin
repositories call `Scripts/dev/plugin-lint-repo.sh <plugins-repo> [<base-rev>]`
from a shell checkout at their pinned ref.

For a full audit or regressions inside the assigned test VM:

```
python3 -B Scripts/dev/plugin-lint.py --root builtin/plugins --catalog builtin/plugins/registry.json
python3 -B Scripts/dev/plugin-lint-selftest.py
```

`Scripts/dev/qmllint.sh` with no paths includes built-in QML. Its native import
setup and the container hook share the source-backed metadata boundary described
in `Scripts/dev/native-metadata/README.md`; no installed runtime module is edited.

First container run builds the image (~2 minutes); later runs reuse the cached
image until the Dockerfile or the `atmo-dev` wrapper changes.

To activate it on your clone (one-time setup):

```
git config core.hooksPath .githooks
```

To restore default behavior:

```
git config --unset core.hooksPath
```

## Cold-Load Smoke Test

After any QML change, verify the shell loads from a cold start:

```
qs -c atmosphera -d
```

Expect exit code 0. Live-reload testing alone is insufficient — it lazy-loads
modules and can miss parser errors that trigger only on a fresh start.

> **Run this in a test VM, never on your host session.** Restarting a live
> shell takes down the running desktop; the dev container has no
> Wayland/QuickShell runtime. Container-local VFS generation (above) is a
> headless tooling detail, not a substitute for a VM cold-load.
