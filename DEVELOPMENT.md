# Atmosphera — Development

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
