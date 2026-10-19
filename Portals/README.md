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
| `Read` | `(ss) -> v` | deprecated; the impl wraps **once** — the daemon adds the second variant layer itself for the deprecated frontend `Read` |
| `ReadOne` | `(ss) -> v` | single variant layer, relayed verbatim by the daemon |
| `ReadAll` | `(as) -> a{sa{sv}}` | all namespaces/keys |
| `SettingChanged` (signal) | `(ssv)` | emitted live on theme changes (same single wrap) |

Namespace `org.freedesktop.appearance`, keys:

- `color-scheme` (`u`): `1` = prefer dark, `2` = prefer light. The shell
  always has a concrete scheme, so it never reports `0` (no preference).
  Sourced from `Settings.data.colorSchemes.darkMode`. The payload is
  `u`-typed exactly — strict clients (libadwaita) validate the type and
  silently fall back on a mismatch.
- `accent-color` (`(ddd)`): sRGB triple in `[0,1]`, sourced from
  `AtmoColor.mPrimary`.

Both keys are served spec-shaped in `Read`/`ReadOne`/`ReadAll` (the
`a{sa{sv}}` reply shape comes from dbusqml's bundled
`impl.portal.Settings` type catalog; the accent struct rides inside the
variant payload), and `SettingChanged` is emitted live for both.

Unknown namespaces or keys are answered with a backend
`org.freedesktop.portal.Error.NotFound` error naming the setting; the
daemon converts backend errors to the frontend `NotFound`, which strict
clients treat as "unsupported key" and fall back from cleanly.

## Served interface: FileChooser

`org.freedesktop.impl.portal.FileChooser` at `/org/freedesktop/portal/desktop`:

| Member | Signature | Notes |
| --- | --- | --- |
| `OpenFile` | `(osssa{sv}) -> (u a{sv})` | open files or folders, optional multi-select |
| `SaveFile` | `(osssa{sv}) -> (u a{sv})` | single save target: filename field + inline overwrite confirm |
| `SaveFiles` | `(osssa{sv}) -> (u a{sv})` | destination folder; return the supplied names in order, confirming each replacement |

Response codes: `0` ok (`results` carries `uris`), `1` cancelled, `2`
error.

The method reply is the response, **deferred**: the D-Bus call is held
open (`holdReply()`) while the dialog is up and answered only when the
user finishes — the reply carries `(u response, a{sv results})`, with
`uris` marshaled as a typed `as` variant (`new DBusQML.variant(paths,
"as")`; a plain array infers `av` and xdg-desktop-portal silently drops
it).

Each call also gets a per-call `org.freedesktop.impl.portal.Request`
adaptor at the caller-supplied handle path; its `Close()` cancels the
dialog and replies `(1, {})`. The adaptor is destroyed when the call
settles, freeing the bus path immediately.

`FileChooserPortal` creates a fresh `Services/Files/FileRequest` and a
`Modules/FileChooser/FileChooserWindow` per handle. The service owns option
decoding, validation, overwrite checks and exactly one result. Its `FileBrowser`
owns the folder and listing; `FileSelection` owns selection. Views bind to those
services and send intents. Successful requests remember their folder per app
through `FileChooserMemory`; cancellation never changes that memory.

Options retain their portal shapes: glob/MIME filters and `current_filter`,
combo/boolean choices, `accept_label`, multiple/directory selection,
`current_folder`, `current_file`, `current_name`, and SaveFiles `files`.
Successful replies type `uris` as `as`, `choices` as `a(ss)`, `current_filter`
as `(sa(us))` and `writable` as `b`. Saves only return destinations: the chooser
does not create or overwrite files. Folder failures appear inline in plain
language, naming the folder, while the current listing remains coherent.
`writable` is an implementation result consumed by xdg-desktop-portal, not a
frontend `Response` key; frontend clients receive URIs, choices and the filter.

The layer-shell window opens focused and centred on the app's focused output
and stays above the app. `parent_window` and `modal` are accepted best effort;
true foreign-window parenting requires compositor `xdg-foreign` support.
Frontend `Request.Close`, application exit (relayed by xdg-desktop-portal),
portal-daemon loss and window cancellation all cancel the request once.

Settings panels and setup callers use `PortalFilePicker` + `FileChooserClient`
through **`org.freedesktop.portal.Desktop`**, just like external applications.
Each operation supplies a unique handle token and installs its `Response`
subscription on the predicted handle before calling `OpenFile`. A same-bus
barrier orders the subscription before the call. The client obtains its
connection's unique name by briefly claiming a private D-Bus name and asking
`GetNameOwner`, then releases that claim. `close()` sends `Request.Close`;
response, method error and service loss settle the operation only once.
`PortalFilePicker` keeps its existing properties, `open()` / `openFilePicker()`,
`close()`, `accepted(paths)` and `cancelled()` interface.

Quick look supports WebP through required `qt6-imageformats`. Optional
`qt6-webengine` supplies QtPdf for PDF preview; without it PDFs show file info.

## Served interface: Inhibit

`org.freedesktop.impl.portal.Inhibit` (full v3 surface) at
`/org/freedesktop/portal/desktop`:

| Member | Signature | Notes |
| --- | --- | --- |
| `Inhibit` | `(ossua{sv}) -> ()` | grant + map onto `IdleInhibitorService`; held until the impl Request is `Close()`d |
| `CreateMonitor` | `(ooss) -> (u)` | session for `StateChanged` snapshots; `0` granted |
| `QueryEndResponse` | `(o) -> ()` | accepted no-op |
| `StateChanged` (signal) | `(oa{sv})` | emitted on the impl interface; the daemon re-emits to the session owner |

Policy: **grant + toast.** Every valid request is granted — the daemon
already enforces the permission store before calling us. A toast notifies
the user when an app starts holding idle (deduplicated per `appId`, on
the 0→1 transition, since media players toggle inhibit on play/pause).
The only error path is genuinely malformed state (duplicate monitor
session).

Flag mapping, honestly: the `Inhibit` flags (`1` logout, `2`
user-switch, `4` suspend, `8` idle) are all accepted but map onto idle
inhibition only — which transitively blocks idle-triggered lock and
idle-triggered suspend, but never a manual `systemctl suspend` or
logout. Rejecting suspend-bearing calls would break apps that pass
`4|8`; upstream GNOME's fdo fallback accepts idle only for the same
reason. There is no logind sleep-block integration.

State sources for `StateChanged`:

- `screensaver-active` — the shell's lock screen active state (the lock
  screen is the screensaver equivalent; no separate screensaver exists).
- `session-state` — always `1` (Running). Nothing on niri+logind emits
  Query End/Ending (no session manager), so the backend never reports
  `2`/`3` and `QueryEndResponse` is treated as an accepted no-op. This
  is documented rather than faked.

Teardown: an `Inhibit` is held until the daemon closes the impl
`Request` — on app-initiated `Request.Close` or automatically when the
app's bus name vanishes. A monitor session is torn down by `Close()` on
the impl `Session` (the Request at `handle` may never see `Close`).
Unknown handles on close are tolerated (shell restarted under a live
daemon).

## Files

| File | Purpose |
| --- | --- |
| `atmosphera.portal` | Backend registration file (installed to `/usr/share/xdg-desktop-portal/portals/`) |
| `niri-portals.conf` | Backend preference for niri sessions (installed to `/usr/share/xdg-desktop-portal/`) |
| `SettingsPortal.qml` | Settings interface backend (DBusAdaptor) |
| `FileChooserPortal.qml` | FileChooser interface backend (DBusAdaptor, deferred replies, per-call Request objects) |
| `InhibitPortal.qml` | Inhibit interface backend (DBusAdaptor, per-call Request/Session adaptors, StateChanged emission) |
| `../Services/Files/` | Browsing, selection, request validation, memory, places, file types and previews |
| `../Modules/FileChooser/` | Per-request layer-shell window and presentation components |
| `PortalFilePicker.qml` | In-shell widget shim → `FileChooserClient` |
| `FileChooserClient.qml` | Frontend client with pre-call subscription and cancellable single-settle operations |
| `README.md` | This file |

## Routing / precedence

xdg-desktop-portal picks a backend per interface. With no config it falls
back to directory-read order ("last-resort fallback") — **not**
alphabetical — so with `xdg-desktop-portal-gtk` installed, gtk wins both
interfaces and the shell's backend never gets called. The package
therefore ships `niri-portals.conf`:

```ini
[preferred]
default=atmosphera
```

which pins the shell's backend for every interface it implements (other
interfaces still fall through to whatever else is installed). To override
per-user, use `~/.config/xdg-desktop-portal/portals.conf` and
`systemctl --user restart xdg-desktop-portal`.

## Screencast (out of scope)

On niri, portal screencast is only served by `xdg-desktop-portal-gnome`
(niri is smithay, not wlroots, so `-wlr` cannot serve it). Users who need
browser/OBS screen sharing install `xdg-desktop-portal-gnome` themselves —
it is listed as an optdepend of the `atmosphera` package, never a hard
dependency.

## Dependencies

- `xdg-desktop-portal` (must be running on the session bus)
- `qt6-dbusqml` >= 0.9.0 (`DBusAdaptor` server-side support: co-located
  adaptors at one path, deferred replies, Properties marshal guards,
  per-call adaptor ownership preserved through dispatch, and the bundled
  Inhibit catalog driving reply shapes and truthful served introspection)
