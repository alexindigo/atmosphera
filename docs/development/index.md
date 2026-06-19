# Setup & Run

## Prerequisites

**Engine:** [`noctalia-qs`](https://github.com/noctalia-dev/noctalia-qs) (AUR) — the Quickshell fork that powers the shell.

### Arch Linux

```sh
sudo pacman -S qt6-multimedia imagemagick brightnessctl ffmpeg python wlr-randr
```

Engine (from AUR):

```sh
yay -S noctalia-qs
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

The shell is QML-based and does not need compilation. Install the engine (`noctalia-qs`) as a dependency.

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
