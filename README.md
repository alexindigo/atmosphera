# Atmosphera

> **Project Status: Active Development / Advanced Fork**
> Atmosphera is a desktop shell for Niri and Hyprland with expanded customization, forked from the frozen QML version of Noctalia. While the upstream project [shifted its focus away from the v4 codebase](https://noctalia.dev/blog/announcing-noctalia-v5) for a complete rewrite, this powerful QML architecture has been preserved here to serve as the launchpad for a highly modular, deeply customizable desktop environment.

**_elevating your workspace atmosphere_**

---

## What is Atmosphera?

**Atmosphera** is a robust, highly extensible desktop framework designed specifically for **Niri** and **Hyprland** compositors. Built on top of the flexible and expressive Quickshell (Qt/QML) architecture inherited from Noctalia, it represents a core shift in design philosophy: moving away from a locked-down, purely minimal desktop shell into a highly customizable, multi-layered environment.

### Why this Fork?

Atmosphera is born out of deep respect and gratitude for the Noctalia project. The original team poured immense care into crafting a stable, elegant, and highly capable Qt/QML foundation—without their brilliant groundwork, this project simply would not exist.

As the upstream project shifts its focus to a brand-new architecture, Atmosphera embraces this mature codebase to celebrate, expand, and evolve its potential into the next generation:

* **Unlocked Customization:** Extending the existing layout mechanics to allow deeper, unrestrained configuration of the visual environment.
* **Paradigm Versatility:** Bridging the gap between classic desktop logic and dynamic workflows, allowing users to comfortably adapt the environment to their existing muscle memory.
* **Deep Extensibility:** Moving far beyond basic configuration files by introducing versatile plugin types and developer hooks, allowing the shell's core functionality to be dynamically expanded and remixed.

---

## Preview

https://github.com/user-attachments/assets/bf46f233-8d66-439a-a1ae-ab0446270f2d

<details>
<summary>Screenshots</summary>

![Dark 1](/Assets/Screenshots/noctalia-dark-1.png)
![Dark 2](/Assets/Screenshots/noctalia-dark-2.png)
![Dark 3](/Assets/Screenshots/noctalia-dark-3.png)

![Light 1](/Assets/Screenshots/noctalia-light-1.png)
![Light 2](/Assets/Screenshots/noctalia-light-2.png)
![Light 3](/Assets/Screenshots/noctalia-light-3.png)

</details>

---

## Requirements

- Wayland compositor (see supported compositors below)
- Quickshell: [quickshell](https://git.outfoxxed.me/quickshell/quickshell) **(upstream, ≥ 0.3.0)**

  Atmosphera previously ran on the `noctalia-qs` fork. The migration branch
  moves to upstream Quickshell, which is where new development, bug fixes,
  and compositor-protocol support land — the fork is no longer maintained.

  **Why ≥ 0.3.0:** the branch targets upstream's API surface, which differs
  from the fork it replaces. Per-corner region radii use upstream's
  `PendingRegion` semantics (`undefined` inherits the base radius; a numeric
  value is an explicit override — noctalia's `CornerState` enum does not
  exist upstream), process spawning relies on the `-n` no-duplicate flag
  (upstream defaults it OFF; noctalia had it ON), and IPC calls use
  upstream's stricter argument-count handling. **0.3.0 is the version tested
  on niri and MangoWC; earlier versions are untested.**

---

## Getting Started

**New to Atmosphera?**
Check the [installation guide](https://github.com/alexindigo/atmosphera/releases) and [FAQ](https://github.com/alexindigo/atmosphera/issues) to get up and running!

---

### Arch Linux (AUR)

```bash
yay -S atmosphera      # release
yay -S atmosphera-git  # git master
```

If AUR is unavailable, install directly from the GitHub mirrors:

```bash
# git master
git clone https://github.com/alexindigo/aur-atmosphera-git.git
cd aur-atmosphera-git && makepkg -si

# release
git clone https://github.com/alexindigo/aur-atmosphera.git
cd aur-atmosphera && makepkg -si
```

> **Note — upstream Quickshell.** Since v0.6.0, Atmosphera runs on
> **upstream [quickshell](https://git.outfoxxed.me/quickshell/quickshell)**
> (≥ 0.3.0), not the `noctalia-qs` fork. Both AUR packages above carry the
> migration; the compositor IPC modules are on the AUR as `qt6-niriqml` and
> `qt6-mangowcqml`.

### Manual install (from source, no AUR helper)

For installing the git `main` branch without an AUR helper.

**1. Install runtime dependencies**

```bash
# from the official repos
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-multimedia \
  imagemagick brightnessctl ffmpeg python python-dbus python-gobject \
  wlr-randr cliphist wlsunset

# QML helper libs from the AUR (or build from source)
yay -S --needed qt6-dbusqml qt6-xdgiconqml-git qt6-niriqml qt6-mangowcqml
```

**2. Build and install the niri IPC module (niri sessions, from source)**

```bash
git clone https://github.com/alexindigo/niriqml.git
cd niriqml
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build --prefix /usr   # installs libniriqml + QML module
cd ..
```

**3. Build and install the mangowc IPC module (MangoWC sessions, from source)**

```bash
git clone https://github.com/alexindigo/mangowcqml.git
cd mangowcqml
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build --prefix /usr   # installs libmangowcqml + QML module
cd ..
```

**4. Install the shell**

```bash
git clone https://github.com/alexindigo/atmosphera.git
cd atmosphera

# shell tree (plain QML — no build step)
sudo install -dm755 /etc/xdg/quickshell/atmosphera
sudo cp -r ./* /etc/xdg/quickshell/atmosphera/
sudo rm -rf /etc/xdg/quickshell/atmosphera/dev /etc/xdg/quickshell/atmosphera/tmp
echo "0.1.0-dev" | sudo tee /etc/xdg/quickshell/atmosphera/VERSION

# dispatcher + integration units
sudo install -Dm755 Scripts/bash/atmosphera /usr/local/bin/atmosphera
sudo ln -sf atmosphera /usr/local/bin/atmosphera-session
sudo ln -sf atmosphera /usr/local/bin/atmosphera-settings
sudo ln -sf atmosphera /usr/local/bin/atmosphera-lock
sudo install -Dm644 Scripts/systemd/atmosphera-keyd-reload.service /usr/lib/systemd/system/atmosphera-keyd-reload.service
sudo install -Dm644 Scripts/systemd/xremap-atmosphera.service /usr/lib/systemd/user/xremap-atmosphera.service
sudo install -Dm644 Scripts/udev/80-atmosphera-uinput.rules /usr/lib/udev/rules.d/80-atmosphera-uinput.rules
sudo install -Dm644 Scripts/polkit/atmosphera-keyd.rules /usr/share/polkit-1/rules.d/atmosphera-keyd.rules
```

**5. Run it**

```bash
# niri session
XDG_CURRENT_DESKTOP=niri qs -c atmosphera

# MangoWC session
XDG_CURRENT_DESKTOP=mango qs -c atmosphera
```

`XDG_CURRENT_DESKTOP` selects the compositor backend; `qs` is upstream
Quickshell. The shell degrades gracefully if an IPC module is missing
(empty workspaces for that compositor) — install the module matching your
compositor for full workspace/window integration.

---

## Per-compositor setup

Beyond the shell itself (and upstream Quickshell ≥ 0.3.0), each compositor
needs a small amount of extra wiring: an IPC module for workspace/window
integration, and a way to launch the shell at session start. Listed in
order of support depth.

### Niri

- **IPC module:** `qt6-niriqml` (built from source in step 2 of the manual
  install; AUR: `qt6-niriqml`). Provides workspaces, windows, focus, and
  overview state over niri's socket. Detection is automatic via
  `NIRI_SOCKET`.
- **Session wiring:** run the bundled setup script once:
  ```bash
  atmosphera-niri-setup
  ```
  It composes `~/.config/niri/atmosphera-session.kdl` (your base config +
  the Atmosphera layers), adds `spawn-at-startup "qs" "-n" "-c" "atmosphera"`,
  and switches the running session to it — without touching your
  `config.kdl`.
- **Manual equivalent** (if you prefer your own config): include
  `Configs/niri/atmosphera.kdl` and add the spawn line above to your niri
  config.

### Hyprland

- **IPC module:** none. Hyprland integration uses Quickshell's **built-in**
  `Quickshell.Hyprland` module — workspaces, toplevels, and focus work out
  of the box. Detection is automatic via `HYPRLAND_INSTANCE_SIGNATURE`.
- **Session wiring:** add a launch line to `~/.config/hypr/hyprland.conf`:
  ```bash
  exec-once = qs -n -c atmosphera
  ```
  No extra packages beyond the shell + Quickshell.

### MangoWC

- **IPC module:** `qt6-mangowcqml` (built from source in step 3 of the
  manual install; AUR: `qt6-mangowcqml`). Talks to mangowc's `mmsg` JSON socket for
  workspaces (tags), windows, focus, keymode, and keyboard layout. Detection
  requires `XDG_CURRENT_DESKTOP=mango`.
- **Session wiring:** mangowc's `config.conf` has **no `exec-once`/autostart
  keyword** — autostart is the session launcher's job, which is also where
  the desktop identity gets set. On a bare tty session, add to
  `~/.bash_profile` (or your display-manager session file):
  ```bash
  if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export XDG_CURRENT_DESKTOP=mango
    exec mango
  fi
  ```
  then have Atmosphera start once mangowc is up (e.g. via a
  `qs -n -c atmosphera` line in your session autostart, or bound to a key
  with `bind=...,spawn,qs -n -c atmosphera`). The `XDG_CURRENT_DESKTOP=mango`
  export is what selects the MangoWC backend.

### Other compositors

**Sway** (and i3-compatible) uses the built-in `Quickshell.I3` module, and
**Labwc** / **Scroll** use built-in Quickshell Wayland support — no extra
IPC module for any of these. Other Wayland compositors may work but could
require additional configuration for compositor-specific features like
workspaces and window management.

---

## Scope

Atmosphera is a **desktop shell**, not a full desktop environment. It provides the visual layer that sits on top of your Wayland compositor (bars, panels, notifications, a dock, and widgets) but it intentionally stays within that boundary. Understanding this helps set the right expectations for feature requests.

### What Atmosphera does

Atmosphera focuses on the things a shell is responsible for: status bar, panels, application launcher, notifications, lock screen, idle management, OSD, theming, wallpapers, desktop widgets, dock, and multi-monitor support.

### What belongs in a plugin

If a feature is useful to some users but not essential to the core shell experience, it's a great candidate for a [plugin](./docs/plugins/). The plugin system is designed to make this easy: plugins can add bar widgets, panels, launcher providers, desktop widgets, and more.

Some examples of features that are better suited as plugins:
- Compositor-specific extras (e.g., Steam overlay for Hyprland)
- Hardware-specific controls (e.g., laptop fan profiles, battery thresholds)
- Third-party service integrations (e.g., smart home controls, Tailscale)
- Niche productivity tools (e.g., Pomodoro timer, RSS reader, Docker manager)
- Alternative visualizations or widgets

If you have an idea that fits this category, consider [building a plugin](./docs/development/) for it!

### What falls outside our scope

Some features go beyond what a desktop shell can or should do. These are typically responsibilities of the compositor, a dedicated application, or the system itself:

- **File management**: use a file manager application
- **Display/login greeter**: this runs before the shell and is managed separately
- **Window management and overview**: workspace switching and window tiling are compositor responsibilities
- **Removable drive mounting**: handled by system services like udisks and desktop applications
- **Screen mirroring/casting**: managed by the compositor or dedicated tools

We appreciate feature suggestions, but if a request falls into this category, it's likely outside what Atmosphera can provide. When in doubt, feel free to ask in our [GitHub Issues](https://github.com/alexindigo/atmosphera/issues).

---

## Contributing

We welcome contributions of any size — bug fixes, new features, documentation improvements, or custom themes and configs.

**Get involved:**
- **Found a bug?** [Open an issue](https://github.com/alexindigo/atmosphera/issues/new)

---

## Acknowledgments

Atmosphera is a fork of **Noctalia Shell**. Thanks to all the [contributors](https://github.com/noctalia-dev/noctalia-shell/graphs/contributors) who built and inspired this project — see [THANKS.md](./THANKS.md).

---

## License

GNU General Public License v3.0 — see [LICENSE](./LICENSE) for details.

This project is a fork of [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell), originally released under the MIT License. See [THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md) for original copyright and license information on incorporated code.
