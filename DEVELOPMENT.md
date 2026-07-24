# Atmosphera — Development

## Devcontainer

A devcontainer is provided at `.devcontainer/` for consistent development tooling.
It uses Arch Linux base and includes Qt6 declarative tools (qmllint, qmlformat,
qmlls), Python, shellcheck, shfmt, and tree-sitter.

**Editors:**
- **VSCode** — auto-detects `.devcontainer/` and prompts to "Reopen in Container"
- **JetBrains** — Dev Containers plugin (JetBrains Toolbox → Plugins)
- **CLI** — Docker image can be built and used directly:

  ```
  docker build .devcontainer/ -t atmosphera-dev:local
  docker run -it --rm -v $(pwd):/workspaces/atmosphera atmosphera-dev:local bash
  ```

**What runs in the container:** linting, formatting, and non-Wayland tooling.

**What stays on host:** QuickShell runtime (`qs`, `atmosphera-session`), cold-load
smoke tests (`qs -c atmosphera -d`), and anything requiring Wayland / DBus / systemd.

## QML Linting

```
Scripts/dev/qmllint.sh [path ...]
```

Uses Qt6's qmllint with severity levels configured in `.qmllint.ini`.

**With devcontainer:** recommended — tools are pre-installed. Run inside the
container (VSCode terminal or `docker run`).

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
and qmllint on staged QML files, blocking commits with errors.

**Docker required.** The hook builds and runs the devcontainer image to execute
checks. First run builds the image (~2 minutes); subsequent runs use the cached
image.

To activate it on your clone (one-time setup):

```
git config core.hooksPath .githooks
```

To bypass the hook (e.g., Docker not available):

```
git commit --no-verify
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

> **Note:** This must run on the host (QuickShell runtime is not in the container).
