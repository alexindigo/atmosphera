# Setup & Run

## Prerequisites

**Engine:** [`quickshell`](https://git.outfoxxed.me/quickshell/quickshell) — upstream Quickshell, available in the Arch `extra` repo.

### Arch Linux

```sh
sudo pacman -S quickshell qt6-multimedia imagemagick brightnessctl ffmpeg python wlr-randr
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

## Build

The shell is QML-based and does not need compilation. Install the engine (`quickshell`) as a dependency.

## Install

### From source (user install)

```sh
mkdir -p ~/.config/quickshell/atmosphera
cp -r . ~/.config/quickshell/atmosphera/
```

Then install the CLI dispatcher to your PATH:

```sh
./install/install_scripts.sh
```

This places `atmosphera` in `~/.local/bin/`. The shell itself is launched
with `qs -c atmosphera`, but all helper commands (lock, settings, bindings,
alerts, IPC, etc.) are reached through `atmosphera <subcommand>`.

Then run `qs -c atmosphera`.

### System-wide (manual)

```sh
sudo mkdir -p /etc/xdg/quickshell/atmosphera
sudo cp -r . /etc/xdg/quickshell/atmosphera/
sudo ./install/install_scripts.sh /usr/local/bin
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

## Dev tools

| Tool | Purpose |
|------|---------|
| `Scripts/dev/qmlfmt.sh` | Format QML files (requires `qmlformat` from `qt6-declarative`) |
| `Scripts/dev/build-settings-search-index.py` | Rebuild settings search index |
| `Scripts/dev/apply-patch.sh` | Apply upstream patches |
| `Scripts/dev/get-patches-from-commits.sh` | Generate patch files from upstream commits |
| `Scripts/dev/shaders-compile.sh` | Pre-compile GLSL shaders |

## Testing

### Run from source

```sh
qs -c atmosphera -r /path/to/atmosphera
```

### Test notifications

```sh
./Scripts/dev/notifications-test.sh
```

### QML live edit

With the shell running, edit any `.qml` file. The plugin system watches for file changes and hot-reloads when debug mode is enabled. For core files (not plugins), restart `qs`.
