# niri (macOS environment)

macOS-style compositor keybindings for niri.

## Files

- `atmosphera-shortcuts-macos.kdl` — deployed to `~/.config/niri/atmosphera-shortcuts-macos.kdl`.

## Include

`atmosphera-bindings-apply` adds this line to `~/.config/niri/config.kdl` (idempotent):

```kdl
include "atmosphera-shortcuts-macos.kdl"
```

Removing the environment removes the include but leaves the file on disk (harmless).

## Ghost modifier

The file sets `mod-key "ISO_Level5_Shift"` which neutralizes upstream `Mod+` binds
without touching upstream files. All binds here use explicit `Super+`, `Ctrl+`, `Alt+`.

## Runtime dependency

Requires the `atmosphera` CLI dispatcher on PATH (installed by `install/install_scripts.sh`
or via the Nix package). The niri config uses `spawn "atmosphera" "close-tab"` which
delegates to the close-tab helper.
