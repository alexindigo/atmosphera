# macOS environment

macOS-style keyboard shortcuts for the atmoshera desktop.

## What it does

- **Modifier swap** on the internal laptop keyboard (via keyd and/or xremap modmap):
  - Physical Ctrl (corner) → Super/Cmd
  - Physical Super (Win) → Alt/Option
  - Physical Alt (next to Space) → Ctrl/Cmd
- **Text navigation**: Cmd+arrows → Home/End/document extremes
- **Word navigation**: Option+arrows → Ctrl+arrows
- **Terminal fixes**: Ctrl+C/V/X remapped to Ctrl+Shift+C/V/X in terminal apps
- **App Switcher**: Cmd+Tab → niri's Super+Tab window switcher
- **Window management**: Cmd+W/F/O/Space for close/fullscreen/overview/launcher
- **Screenshots**: Print/Super+Shift+5 for screen and recording
- **Typographic characters**: Alt+key emits macOS Option-key symbols via wtype
- **Zed editor**: full macOS keymap including terminal context forwarding

## Layers

See `keyd/README.md`, `niri/README.md`, `xremap/README.md`, `zed/README.md` for per-layer
detail.

## Dependencies

Required:
- `niri` — compositor
- `wtype` — used by close-tab-or-window and by niri binds for typographic characters
- `xremap` (with the niri backend, e.g. `xremap-niri-bin` on AUR)

Optional but recommended for full experience:
- `keyd` — hardware-level modifier swap and Cmd+Click support
