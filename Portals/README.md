# Portals

Atmosphera portal backends that register with `xdg-desktop-portal` to serve desktop portal interfaces — replacing the need for GNOME or KDE portal packages on compositors like Niri and Hyprland.

## Why

Without a portal backend for `org.freedesktop.impl.portal.Settings`, apps like Zed, Electron, and modern Qt/KDE apps call `portal.Read("org.freedesktop.appearance", "color-scheme")` and get no answer — defaulting to Light mode regardless of how the shell is configured.

Traditional solutions pull in a full DE portal package (`xdg-desktop-portal-gtk` → GSettings stack, `xdg-desktop-portal-kde` → KConfig), which is unnecessary on a standalone compositor.

By providing our own minimal backends, the shell directly serves what it already knows.

## How it works

1. The main `xdg-desktop-portal` daemon owns `org.freedesktop.portal.Desktop` on the session bus.
2. Portal backends register via `.portal` files (discovered at startup). Each declares which D-Bus name and interfaces it implements.
3. When an app like Zed calls `org.freedesktop.portal.Settings.Read("org.freedesktop.appearance", "color-scheme")`, it talks to the portal daemon — not to us directly.
4. The daemon looks up `.portal` files, finds our `atmosphera.portal`, and delegates the call to our backend at `org.freedesktop.impl.portal.atmosphera`.
5. Our service responds with the current color-scheme, the daemon passes it back to the app.
6. Multiple backends can coexist — each handles the interfaces it implements, and unclaimed ones fall through.

The routing flow:

```
App (Zed)                   xdg-desktop-portal            Our backend
    │                              │                            │
    │  Settings.Read()             │                            │
    ├─────────────────────────────►│                            │
    │                              │  looks up .portal files    │
    │                              │  → delegates to atmosphera │
    │                              ├───────────────────────────►│
    │                              │  Read() response           │
    │                              │◄───────────────────────────┤
    │  result (dark/light)         │                            │
    │◄─────────────────────────────┤                            │
```

## Backend files

Each interface gets its own `.portal` file and D-Bus name. This keeps them modular: interfaces can be enabled/disabled by renaming files, and user plugins can claim their own D-Bus name to replace a built-in backend.

| File | D-Bus name | Interface | Purpose |
|------|-----------|-----------|---------|
| `atmosphera-settings.portal` | `org.freedesktop.impl.portal.atmosphera-settings` | Settings | Color scheme, fonts |
| `atmosphera-screenshot.portal` | `org.freedesktop.impl.portal.atmosphera-screenshot` | Screenshot | Screen capture |
| `atmosphera-filechooser.portal` | `org.freedesktop.impl.portal.atmosphera-filechooser` | FileChooser | Open/save dialogs |

A plugin can override any interface by owning its D-Bus name — the portal doesn't care which process claims it, only that somebody does.

## Priority

Backends are tried alphabetically by filename within each directory. Filenames are sufficient for priority — `atmosphera-` sorts before `gnome-`, so ours are tried first.

If you have a DE installed, the system config at `/usr/share/xdg-desktop-portal/portals/` coexists with your user config at `~/.config/xdg-desktop-portal/portals/`. To pin a specific backend per interface, use `portals.conf`:

```ini
[preferred]
org.freedesktop.impl.portal.Settings=atmosphera-settings
org.freedesktop.impl.portal.FileChooser=kde
```

## Installation

```sh
mkdir -p ~/.config/xdg-desktop-portal/portals
ln -sf /path/to/atmosphera/Portals/atmosphera-settings.portal ~/.config/xdg-desktop-portal/portals/
ln -sf /path/to/atmosphera/Portals/atmosphera-screenshot.portal ~/.config/xdg-desktop-portal/portals/
ln -sf /path/to/atmosphera/Portals/atmosphera-filechooser.portal ~/.config/xdg-desktop-portal/portals/
```

For system-wide installs the AUR package should put all `.portal` files under `/usr/share/xdg-desktop-portal/portals/`.

## Toggling

Disable an interface by removing its symlink or renaming it to `.disabled`:

```sh
mv ~/.config/xdg-desktop-portal/portals/atmosphera-filechooser.portal{,.disabled}
```

Restart the portal daemon or log out/in. That interface falls through to whatever other backend is available.

## Files

| File | Purpose |
|------|---------|
| `atmosphera.portal` | Backend registration file (desktop-entry format) |
| `SettingsPortal.qml` | Settings interface — responds to color-scheme queries |
| `README.md` | This file |
| `TODO.md` | Next steps |

## Dependencies

- `xdg-desktop-portal` (must be running on the session bus)
- A D-Bus QML library (in-development at `github.com/alexindigo/dbus-qml`)
