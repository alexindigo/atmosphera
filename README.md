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

> **Note — upstream Quickshell migration branch.** Atmosphera now runs on
> **upstream [quickshell](https://git.outfoxxed.me/quickshell/quickshell)**
> (not the `noctalia-qs` fork). That switch lives on the
> `feat/niri-overview-map` branch and is **not yet on the AUR** — the AUR
> packages above still target the previous dependency set. To run the
> migration branch, use the manual install below.

### Manual install (migration branch, no AUR)

This installs the `feat/niri-overview-map` branch directly, tracking upstream
Quickshell plus the new compositor IPC libraries. No AUR packages required
for the shell itself (the QML module dependencies are built from source).

**1. Install runtime dependencies**

The packages below come from the official repos / AUR helper as usual. The
two IPC modules (`qt6-niriqml`, `qt6-mangowcqml`) are built from source in
steps 2–3 since they are not yet on the AUR.

```bash
# from the official repos
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-multimedia \
  imagemagick brightnessctl ffmpeg python python-dbus python-gobject \
  wlr-randr cliphist wlsunset

# QML helper libs (AUR or build from source)
yay -S --needed qt6-dbusqml qt6-xdgiconqml-git
```

**2. Build and install the niri IPC module (niri sessions)**

```bash
git clone https://github.com/alexindigo/niriqml.git
cd niriqml
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build --prefix /usr   # installs libniriqml + QML module
cd ..
```

**3. Build and install the mangowc IPC module (MangoWC sessions)**

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
git clone -b feat/niri-overview-map https://github.com/alexindigo/atmosphera.git
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

## Wayland Compositors

Atmosphera provides native support for **Niri**, **Hyprland**, **Sway**, **Scroll**, **Labwc** and **MangoWC**. Other Wayland compositors may work but could require additional configuration for compositor-specific features like workspaces and window management.

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
