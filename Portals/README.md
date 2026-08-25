# Portals

Atmosphera portal backend that registers with `xdg-desktop-portal` to serve
desktop portal interfaces — replacing the need for GNOME or KDE portal
packages on compositors like niri and Hyprland.

## Why

Without a portal backend for `org.freedesktop.impl.portal.Settings`, apps
like Firefox, Zed, Electron, and modern Qt/KDE apps call
`portal.Read("org.freedesktop.appearance", "color-scheme")` and get no
answer — defaulting to Light mode regardless of how the shell is configured.

Traditional solutions pull in a full DE portal package
(`xdg-desktop-portal-gtk` → GSettings stack, `xdg-desktop-portal-kde` →
KConfig), which is unnecessary on a standalone compositor.

By providing our own minimal backend, the shell directly serves what it
already knows — and the `atmosphera` package can truthfully
`provides=('xdg-desktop-portal-impl')`, satisfying niri's hard dependency
with no foreign-toolkit portal package.

## How it works

1. The main `xdg-desktop-portal` daemon owns `org.freedesktop.portal.Desktop`
   on the session bus.
2. Portal backends register via `.portal` files (discovered at daemon
   startup). Each declares which D-Bus name and interfaces it implements.
3. When an app calls `org.freedesktop.portal.Settings.ReadOne(
   "org.freedesktop.appearance", "color-scheme")`, it talks to the portal
   daemon — not to us directly.
4. The daemon looks up `.portal` files, finds our `atmosphera.portal`, and
   delegates the call to our backend at
   `org.freedesktop.impl.portal.desktop.atmosphera`.
5. Our service responds with the current value, the daemon passes it back to
   the app.
6. Multiple backends can coexist — each handles the interfaces it
   implements, and unclaimed ones fall through.

The routing flow:

```
App (Firefox)               xdg-desktop-portal            Our backend
    │                              │                            │
    │  Settings.ReadOne()          │                            │
    ├─────────────────────────────►│                            │
    │                              │  looks up .portal files    │
    │                              │  → delegates to atmosphera │
    │                              ├───────────────────────────►│
    │                              │  ReadOne() response        │
    │                              │◄───────────────────────────┤
    │  result (dark/light)         │                            │
    │◄─────────────────────────────┤                            │
```

## Design (v1)

- **Single backend name, single manifest.** One D-Bus name
  (`org.freedesktop.impl.portal.desktop.atmosphera`) and one
  `atmosphera.portal` listing the served interfaces — the same convention
  gnome/gtk/kde/cosmic use. (An earlier branch experiment split
  per-interface names; that modularity is not needed for v1.)
- **In-shell adaptor, no separate daemon.** `SettingsPortal.qml` is a QML
  singleton hosting a `DBusAdaptor` from `qt6-dbusqml` (>= 0.4.0). The shell
  is a long-lived service that already owns D-Bus names, so owning one more
  is consistent with its architecture. The adaptor registers on the session
  bus when the singleton is created at shell startup.

## Served interface

`org.freedesktop.impl.portal.Settings` at `/org/freedesktop/portal/desktop`:

| Member | Signature | Notes |
| --- | --- | --- |
| `Read` | `(ss) -> v` | deprecated; value wrapped in **two** variant layers |
| `ReadOne` | `(ss) -> v` | value wrapped in one variant layer |
| `ReadAll` | `(as) -> a{sa{sv}}` | all namespaces/keys |
| `SettingChanged` (signal) | `(ssv)` | emitted live on theme changes |

Namespace `org.freedesktop.appearance`, keys:

- `color-scheme` (`u`): `1` = prefer dark, `2` = prefer light. The shell
  always has a concrete scheme, so it never reports `0` (no preference).
  Sourced from `Settings.data.colorSchemes.darkMode`.
- `accent-color` (`(ddd)`): sRGB triple in `[0,1]`, sourced from
  `Color.mPrimary`.

Both keys are served spec-shaped in `Read`/`ReadOne`/`ReadAll` (the
`a{sa{sv}}` reply shape comes from dbusqml's bundled
`impl.portal.Settings` type catalog; the accent struct rides inside the
variant payload), and `SettingChanged` is emitted live for both.

## Files

| File | Purpose |
| --- | --- |
| `atmosphera.portal` | Backend registration file (installed to `/usr/share/xdg-desktop-portal/portals/`) |
| `SettingsPortal.qml` | Settings interface backend (DBusAdaptor) |
| `README.md` | This file |

## Routing / precedence

Backends are tried alphabetically by filename within each portal directory;
`atmosphera.portal` sorts before `gnome.portal`/`gtk.portal`. To pin
explicitly, use `~/.config/xdg-desktop-portal/portals.conf`:

```ini
[preferred]
org.freedesktop.impl.portal.Settings=atmosphera
```

then `systemctl --user restart xdg-desktop-portal`.

## Screencast (out of scope)

On niri, portal screencast is only served by `xdg-desktop-portal-gnome`
(niri is smithay, not wlroots, so `-wlr` cannot serve it). Users who need
browser/OBS screen sharing install `xdg-desktop-portal-gnome` themselves —
it is listed as an optdepend of the `atmosphera` package, never a hard
dependency.

## Dependencies

- `xdg-desktop-portal` (must be running on the session bus)
- `qt6-dbusqml` >= 0.4.0 (`DBusAdaptor` server-side support)
