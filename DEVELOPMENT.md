# Development

## Prerequisites

**Engine:** [`noctalia-qs`](https://github.com/noctalia-dev/noctalia-qs) (AUR) — the Quickshell fork that powers the shell. Must be installed separately.

### Arch Linux

```sh
sudo pacman -S qt6-multimedia imagemagick brightnessctl ffmpeg python wlr-randr
```

Engine (from AUR):

```sh
yay -S noctalia-qs   # or paru, your preferred AUR helper
```

Optional runtime:

```sh
sudo pacman -S cliphist wlsunset power-profiles-daemon ddcutil
```

### Nix

```sh
nix develop
```

Or with flakes:

```sh
nix develop github:alexindigo/atmosphera
```

### Debian/Ubuntu

No packages available yet — use Nix or build from source.

---

## Build

The shell is QML-based and does not need compilation. Install the engine (`noctalia-qs`) as a dependency — see [Prerequisites](#prerequisites).

## Install

### From source (user install)

```sh
mkdir -p ~/.config/quickshell/atmosphera
cp -r . ~/.config/quickshell/atmosphera/
```

Then run `qs -c atmosphera`.

### System-wide (manual)

```sh
sudo mkdir -p /etc/xdg/quickshell/atmosphera
sudo cp -r . /etc/xdg/quickshell/atmosphera/
```

### Nix

```sh
nix build github:alexindigo/atmosphera
./result/bin/atmosphera
```

## Run

```sh
qs -c atmosphera
```

Or point to a local checkout:

```sh
qs -c atmosphera -r /path/to/atmosphera
```

With the nix package:

```sh
atmosphera
```

Configuration is loaded from `~/.config/atmosphera/`.

---

## Dev tools

| Tool | Purpose |
|------|---------|
| `Scripts/dev/qmlfmt.sh` | Format QML files (requires `qmlformat` from `qt6-declarative`) |
| `Scripts/dev/build-settings-search-index.py` | Rebuild settings search index |
| `Scripts/dev/apply-patch.sh` | Apply upstream patches with interactive conflict resolution |
| `Scripts/dev/get-patches-from-commits.sh` | Generate patch files from upstream commits |
| `Scripts/dev/shaders-compile.sh` | Pre-compile GLSL shaders |

## Project structure

```
atmosphera/
├── shell.qml                   # Main shell entry point
├── Modules/                    # UI components and panels
├── Services/                   # Backend services
├── Widgets/                    # Reusable UI components (NButton, NTextInput, etc.)
├── Commons/                    # Shared utilities (Logger, Settings, Icons, etc.)
├── Assets/                     # Static assets (color schemes, translations, fonts)
├── Scripts/                    # Development and bash scripts
│   ├── dev/                    # Developer tooling (formatters, patches)
│   └── bash/                   # Runtime bash scripts (templates, services)
├── patches/                    # Upstream cherry-picks
└── nix/                        # Nix packaging
```

### Code organization

| Directory | Purpose |
|-----------|---------|
| `Modules/` | UI panels and major components |
| `Services/` | Logic and backend functionality |
| `Widgets/` | Reusable UI components (`N*` prefixed) |
| `Commons/` | Shared utilities and helpers |

**Service-first:** implement logic in services, keep UI components lightweight and focused on presentation.

**Reuse widgets:** check `Widgets/` before creating new ones.

---

## Git hooks

Hooks are installed in `.git/hooks/`:

- **pre-push** — rejects pushing unsigned commits or tags.

To enable signing:

```sh
git config commit.gpgSign true
git config tag.gpgSign true
git config gpg.format ssh
git config user.signingkey "$(cat ~/.ssh/id_ed25519.pub)"
```

### Lefthook (optional)

`lefthook.yml` adds pre-commit hooks for QML formatting and settings index rebuild. Install [lefthook](https://github.com/evilmartians/lefthook#install) and run `lefthook install` to enable.

---

## Code standards

- **No Qt5Compat** — use modern Qt6 alternatives (`QtQuick.Effects`, `MultiEffect`)
- **Use `Logger.qml`** for logging instead of `console.log`
- **Follow existing patterns** — study similar features before implementing new ones
- **Test with both Niri and Hyprland** where applicable
- **Small, focused PRs** are preferred

---

## Making changes

1. Fork and clone the repo
2. Run `nix develop` or install dependencies manually
3. Make your changes
4. Run `./Scripts/dev/qmlfmt.sh` to format QML
5. Commit with a signed commit: `git commit -S -m "fix: description"`
6. Push and open a pull request

## Testing

### Run the shell from source

```sh
qs -c atmosphera -r /path/to/atmosphera
```

The `-r` flag runs from the repo directory instead of the installed path. Changes to `.qml` files take effect on restart.

### Test notifications

```sh
./Scripts/dev/notifications-test.sh
```

### Test templates

Templates (btop, GTK, Starship, etc.) are applied via:

```sh
./Scripts/bash/template-apply.sh
```

This regenerates config files from `Assets/Templates/` and writes them to `~/.config/atmosphera/templates/`.

### QML live edit

With the shell running, edit any `.qml` file. The plugin system watches for file changes and hot-reloads when debug mode is enabled. For core files (not plugins), restart `qs`.

---

## Upstream patches

Upstream fixes ported to our fork live in `patches/` and are applied via `Scripts/dev/apply-patch.sh`. See `patches/README.md` for workflow details.
