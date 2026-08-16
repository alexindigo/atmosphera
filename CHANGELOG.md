# Changelog

## [0.5.1] — 2026-08-16

### 2026-08-16

**Feature**

A batch of curated defaults was promoted to the schema — framed bar, no bar
capsule, wallpaper-driven colors on by default, dimmer panels (0.55), and the
wallpaper overview/browse view enabled out of the box. Fresh installs get the
new defaults; existing users' explicit values keep winning under the two-layer
settings design. The Notifications settings page also gained a "Send test
notification" button that fires through the real D-Bus path so opacity,
density and location changes can be previewed live.

- feat(settings): promote curated defaults (framed bar, wallpaper colors, dimmer panels) (`7dfc971f4`)
- feat(settings): test-notification button on Notifications panel (`2745ece5d`)

### 2026-08-15

**Feature**

Hardware health landed: the shell reads hwmon labels/crit values and fan RPM
alongside temperatures, warns early when any sensor sustains near-critical
heat (crit-derived thresholds, sustained-poll + hysteresis + rate-limit +
per-sensor mute), keeps a self-trimming fsync'd thermal history log in user
space, and notices at login when the previous shutdown was not clean (given a
machine-side marker). A new System → Hardware health settings sub-tab exposes
the toggles, the power profile selector, live sensor readings, and a CPU
turbo-boost toggle driven by a new polkit-gated D-Bus helper,
`app.atmosphera.HwController`, that writes the pstate/boost sysfs node.
System monitor tooltip and the system stats panel now show hottest core, fan
speed and per-sensor temperatures.

- feat(system): hwmon crit/max/labels + fan RPM reads in SystemStatService (`0b34e5f18`)
- feat(health): HardwareHealthService — thermal early-warning + history logger + unclean-shutdown notice (`e5b73f458`)
- feat(hardware): app.atmosphera.HwController helper + turbo toggle (`8543c7981`)
- feat(settings): Hardware health sub-tab under System (`36c3ca964`)
- feat(visibility): fan/thermal details in SystemMonitor tooltip + SystemStatsPanel (`72a72e0fb`)

### 2026-08-13

**Feature**

The NetworkManager D-Bus migration completed: the wifi radio toggle and
new-network connections (including enterprise 802.1X) now go through raw
D-Bus with error toasts on polkit denial, and VPN connections are listed and
toggled over D-Bus as well. The demo lock screen plugin was rewritten as a
best-practices example of consuming shell domain objects instead of
hand-rolled CLI probes.

- feat(network): wifi radio toggle via raw D-Bus (phase 4) (`5b601808a`)
- feat(network): connect-new via D-Bus AddAndActivateConnection (phase 3 complete) (`45003dd9a`)
- refactor(network): VPNService over D-Bus, gates use nmManager.serviceAvailable (`10367a85d`)
- docs(demo): lockscreen consumes NetworkService domain objects (best practices) (`c0f76fffa`)

### 2026-08-12

**Feature**

The NetworkManager D-Bus migration began: nmcli left the network data plane.
Device/connection state, link details (IP, gateway, DNS, MAC, speed, bitrate),
the wifi AP list with security-type mapping, and connectivity now all come
from D-Bus signals and properties — and disconnect/forget/connect-saved/scan
moved to D-Bus calls as well, fixing the stuck-icon bug where cable-unplug
left the bar showing a stale network.

- feat(network): D-Bus event source for NetworkManager state (phase 1) (`2858b3793`)
- feat(network): device state, link details, wifi list, connectivity via D-Bus (phase 2) (`fa51f3c8d`)
- feat(network): disconnect/forget/connect-saved/scan via D-Bus (phase 3) (`378413466`)

## [0.5.0] — 2026-08-15

### 2026-08-15

**Feature**

The shell now ships with the [Atmosphera plugin registry](https://github.com/alexindigo/atmosphera-plugins)
pre-linked as an enabled, out-of-the-box plugin source — a full conversion of
the upstream Noctalia plugin catalog plus plugins vendored from unmerged
upstream PRs. New installs can browse and install community plugins from
Settings → Plugins without adding a source by hand. The first-run bootstrap
seed was also fixed to actually write the configured default sources (it
previously hardcoded only the Built-in source).

- feat(plugins): add atmosphera-plugins as an out-of-the-box source (`7e4fcb50e`)

### 2026-08-13

**Feature**

The Settings → Appearance → Icons panel became a real icon-set manager:
installed sets can be enabled/disabled and drag-reordered for resolution
priority (persisted in the new `icons.setOrder` setting), with friendly names
instead of raw plugin ids, a live per-set preview filter, and a searchable
fixed-height icon grid. The bundled fallback set is protected from being
disabled since the shell's own UI icons resolve through it.

- feat(settings): Icons panel becomes the icon-set manager (`af4d883e0`)
- feat(settings): icons.setOrder schema + user-controlled icon-set priority (`7d4bd1045`)

### 2026-08-12

**Feature**

The About panel now reports the real installed version: packaged builds read
the VERSION file baked at package time, dev checkouts fall back to
`git describe`, and git-based installs compare the installed commit against
the latest main commit to offer updates.

- feat(version): detect real installed version (VERSION file / git describe) (`f034b1bd8`)

**Fix**

About-panel polish: the commit-hash link now points at this repository and is
clickable on packaged installs, and the QS component is correctly labeled.

- fix(about): point commit-hash link at our repo, make it always clickable (`e2bb9beb3`)
- fix(about): label the QS component as Noctalia QS (`7f40fe721`)

### 2026-08-11

**Feature**

Second wave of the settings overhaul: per-panel override files under
`~/.config/atmosphera/settings/` split user settings into one file per
section, and plugins get user-owned per-plugin settings/config under
`settings/plugins/` with a two-layer merge (plugin-shipped defaults plus user
overrides). The setup wizard's chrome was unified into a shared WizardPanel
component with consistent breadcrumbs, headers, and a guaranteed-scrollable
content area.

The icon set was rebuilt from scratch as per-icon SVGs — 6,114 icons converted
from the legacy Fontello font to individual SVG files (mostly Tabler-sourced),
retiring the `noctalia-icons-legacy` plugin as a separate set.

- feat(settings): per-panel override files under ~/.config/atmosphera/settings/ (`7cee45d56`)
- feat(plugins): user-owned per-plugin settings/config under settings/plugins/ (`a38be566e`)
- feat(icons): full Atmosphera icon set as per-icon SVGs (`88458dde1`)
- feat(icons): retire noctalia-icons-legacy, merged into atmosphera-icons (`a3d09d476`)
- feat(setup-wizard): shared WizardPanel component for wizard chrome (`26179e853`)

**Refactor**

The icon widget family was renamed for clarity: `NIcon*` → `AtmoIcon*` (shell
UI icons) and the app-icon renderer became `AtmoAppIcon`. No user-visible
change.

- refactor(icons): rename NIcon family to Atmo* (`04f2b3425`)
- refactor(icons): rename AtmoIcon to AtmoAppIcon (`1837f15ef`)

**Fix**

- fix(scripts): read bindings.environment from per-panel settings with legacy fallback (`f2864726f`)

### 2026-08-10

**Feature**

Settings became two-layer: the package ships schema-derived defaults and user
writes land as sparse overrides, so defaults track new releases instead of
freezing at first-run values. A per-tab reset-to-defaults button in the
settings header makes recovery one click.

- feat(settings): two-layer settings — schema defaults + sparse user overrides (`7d1a459d2`)
- feat(settings-ui): per-tab reset-to-defaults button in settings header (`89f1db745`)
- feat(plugins): pluginApi.getConfig — two-layer plugin config merge (`a1144063a`)

**Fix**

- fix(xremap): ship udev rule granting input group /dev/uinput access (`8201ea705`)

### 2026-08-09

**Feature**

The macOS bindings environment became self-managing: the shell owns the keyd
layer file (user-writable, applied without sudo) and reloads keyd through a
systemd D-Bus trigger, and xremap runs as an env-gated user service the shell
starts and stops over the session D-Bus. Switching shortcut environments no
longer needs a terminal. fcitx5 input-method state is published on change for
widgets and plugins.

- refactor(keyd): shell-owned layer + systemd D-Bus reload trigger (`258d5a467`)
- feat(keyd): systemd path unit auto-reloads keyd on layer change (`b7c6e4967`)
- feat(keyd): install-time hook + user-owned layer for sudo-less env switching (`b989349b4`)
- feat(xremap): env-gated user service, shell-controlled via session D-Bus (`e5579be77`)
- feat(inputmethod): publish fcitx5-input-state.json on IM change (`1deb5130b`)

**Fix**

- fix(keyd): strip [ids] from the include target; layer() form required (`5cf4b6fed`)
- fix(keyd): scope generated default.conf to built-in keyboard ids (`d7156c137`)
- fix(keyd): use reply.finished pattern for systemd D-Bus call (`4601769ed`)
- fix(inputmethod): use reply.finished for fcitx5 D-Bus calls (`b4c4952fa`)
- fix(inputmethod): accept array-like struct members, not just real Arrays (`525c7a46a`)
- fix(bindings): align macos pack to canonical 2-way Alt↔Super swap (`53215e346`)

### 2026-08-08

**Feature**

A dedicated fcitx5 i18n layer with an IM-switching IPC target, wired into the
niri setup flow.

- feat(i18n): dedicated fcitx5 i18n layer with IM-switching IPC target (`dd6532a51`)

**Fix**

- fix(i18n): add i18n layer to niri-setup CLI (was missing from previous commit) (`963d26586`)

**Docs**

- docs: add Arch Linux install section (AUR + GitHub mirrors) (`e6a85203e`)

### 2026-08-07

**Feature**

The niri session configuration is now composed by the shell through a QML init
chain — compositor includes and reloads are managed for the user.

- feat(session): QML init chain + session-composed niri config (`7810cc54d`)

**Refactor**

niri IPC moved to the typed niriqml API behind a Loader-based wrapper, with a
startup notification when the optional `qt6-niriqml` package is missing.

- refactor(session): drop niri msg CLI fallback, notify on missing niriqml (`468b09e3e`)
- refactor(scripts): session-config flow for niri setup, bindings, switcher (`18575f649`)

**Fix**

- fix(session): add missing Quickshell import for Singleton root (`595c96715`)
- fix(session): resolve socket owner via /proc/net/unix, not fs inode (`d154284e6`)
- fix(dev): declare qt6-xdgiconqml-git dependency (`9526c97b9`)
- chore(pkgbuild): optdepends qt6-niriqml for niri IPC integration (`1a938a559`)

### 2026-08-06

**Feature**

A VM local-dev test loop: the repo bind-mounts into the test VM and packages
build from the working tree, so unpushed commits are testable end-to-end.

- feat(dev): VM local-dev test loop (`382306e90`)

**Fix**

- fix(plugins): eliminate bootstrap seed race on first run (`53e1c0863`)
- fix(niri): spawn-at-startup, comment-safe include, restart hint (`b68d86d27`)
- fix(cli): SELF_DIR auto-detect for system-installed dispatcher (`142cfae4a`)
- fix(scroll-text): fix scrollState/state typo causing phantom marquee text (`32da38d4a`, `c39cbcbce`)
- fix(qml): getAppIconName in ActiveWindow, Color fallbacks in SetupBindingsStep (`f8d596dc5`)
- fix(dev): exclude dev/tmp from PKGBUILD install tree (`a1788a3ff`)

### 2026-08-04

**Fix**

- fix(popupmenu): pass shellScreen to PopupMenuWindow in AllScreens (`8508bd9a8`, `c765fc9f0`)

### 2026-08-02

**Feature**

A reactive `AtmoIcon` wrapper for app icons from XDG themes, and a typed
`NiriIpcBackend` for niri IPC via the niriqml library.

- feat(icons): add AtmoIcon reactive wrapper component (`b4bc15191`)
- feat(niri): add NiriIpcBackend wrapping niriqml typed API (`14259d475`)
- feat(icons): add ThemeIcons.iconNameForAppId helper (`28e1a1b8c`)

**Refactor**

Migrated icon consumers (Bar, Dock, Launcher, AudioPanel, NotificationService,
DesktopAppShortcut, HostService) to the reactive icon components, and replaced
the Quickshell.Niri plugin usage with the niriqml Loader wrapper.

- refactor(icons): migrate Bar widgets to AtmoIcon (`3f66a32cb`)
- refactor(icons): migrate NotificationService to AtmoIcon (`389f4c37f`)
- refactor(icons): migrate Launcher delegates to AtmoIcon (`4d6accf6b`)
- refactor(icons): migrate Dock to AtmoIcon (`854b6dc80`)
- refactor(icons): migrate AudioPanel to AtmoIcon (`d07948a5b`)
- refactor(icons): migrate HostService logo lookup to XdgIcon (`a138ce133`, `ae70b9604`)
- refactor(icons): remove legacy ThemeIcons functions (`85ef573cb`)
- refactor(niri): replace Quickshell.Niri with niriqml via Loader wrapper (`b73ae7d02`)
- refactor(niri): migrate NiriService to Loader-based wrapper (`cc90e4fca`)

**Fix**

- fix(icons): correct AtmoIcon size and path format in DesktopAppShortcut (`9b0b754eb`, `c70a08db3`)
- fix(icons): remove duplicate AtmoIcon in DesktopAppShortcut (`a07480ee4`, `dc6e3ba14`)
- fix(settings): add missing icons to tab entries (`459ee91b3`)

## [0.4.0] — 2026-08-01

### 2026-07-27

**Feature**

Integrated the atmosphera-bindings repository as a self-contained `Bindings/`
module organized by shortcut *environment*. A new step in the setup wizard and
a Settings → General → Shortcuts sub-tab let users opt into a **macOS-style**
shortcut environment that spans keyd (hardware Alt↔Super swap), xremap (text
navigation, word navigation, terminal fixes), niri (window management,
screenshots, Cmd+W close-tab helper), and Zed (editor keymap). Default remains
`"none"` — no behaviour changes for upgrading users. Migration60 seeds the new
`bindings.environment` field so existing settings.json files upgrade cleanly.

Two apply scripts orchestrate deployment: `atmosphera-bindings-apply` handles
all user-space layers (niri include, xremap config, zed keymap) without
elevation, and `atmosphera-bindings-apply-keyd` performs the one-time root
bootstrap that makes `/etc/keyd/atmosphera` an include-file managed by
subsequent user-level toggles. The wizard and settings-tab both fire the
user-space apply as a detached process on selection change, and request a
niri config reload when a niri socket is available.

Nix support: `programs.atmosphera.bindings.environment` (home-module) seeds
the per-user setting; `services.atmosphera.bindings.environment` (NixOS
module) declaratively enables `services.keyd` on `"macos"`, bypassing the
include-file mechanism entirely on NixOS installs. Windows- and KDE-style
environments are planned as additional folders under `Bindings/environments/`.

- Bindings module seeded from atmosphera-bindings + per-layer READMEs (`1e27531f2`, `a3350075a`, `4662d7f97`, `4163493ea`, `d82c016c4`, `13c4a399a`)
- Settings schema + defaults + Migration60 (`be4201733`, `667089935`, `7efdd1a11`)
- User-space + root-side apply scripts (`9665b6964`, `d329ff4da`)
- Wizard step + Shortcuts sub-tab + translations (`6f3c8f477`, `354c504dc`, `fcccca9cd`, `58b2f44f4`)
- Nix package + home-module + NixOS module (`41a1ba279`, `2d8e8a7e4`, `555ba67a9`)

**Chore**

Devcontainer infrastructure hardening. Added `runArgs` to `.devcontainer/devcontainer.json`
(`--memory=12g`, `--memory-swap=12g`, `--pids-limit=2048`, `--cpus=12`) and mirrored the
same caps into `.githooks/pre-commit`'s raw `docker run` so behavior is identical whether
the container is launched by VS Code or the git hook. Paired with a host-side raise of
`docker.slice` (48G/64G/16384) and `/etc/docker/daemon.json` `default-ulimits` (nproc
32768/65536, nofile 65536/131072) — landed separately at the OS level. Together these
make `docker run --user 1000:1000` on this host actually work again after the earlier
conservative post-fork-bomb defaults blocked every containerized dev workflow.

- devcontainer.json runArgs with memory/pids/cpu caps (`39e8802ea`)
- pre-commit hook mirrors container caps (`76474a2fc`)

**Breaking**

The scattered `atmosphera-*` helper scripts (lock, settings, prompt, confirm,
alert, survey, session, niri-setup, bindings-apply, bindings-apply-keyd,
close-tab-or-window) are consolidated into a single `atmosphera` multi-call
dispatcher using the matryoshka pattern. Use `atmosphera <subcommand>` instead
of the standalone script names. No backward-compat symlinks are shipped —
callers must update.

The Nix package's `$out/bin/atmosphera` is now the dispatcher script (was a
symlink to `qs`). `install/install_scripts.sh` now installs only the dispatcher
symlink instead of glob-symlinking all helpers individually.

- Unified CLI dispatcher with child routers for bindings, setup (`78334b0b6`)
- QML call sites updated to `atmosphera bindings apply` (`fb3ad808c`)
- niri spawn paths updated to `atmosphera close-tab` and `atmosphera lock` (`245aacde4`)
- Nix package simplified to dispatcher-only `$out/bin/` (`ca22c56be`)
- `install/install_scripts.sh` simplified (`fe8087313`)
- Install docs updated with dispatcher step (`56709a372`)
- Session module renamed: `atmosphera-session.sh` → `atmosphera-session` (`78334b0b6`)

### 2026-07-28

**Feature**

Session menu buttons now get a "Use shared panel opacity" toggle (Settings →
Session Menu → General), mirroring the Bar's `useSeparateOpacity` pattern.
When enabled, buttons share the panel's background opacity; when disabled, a
custom opacity slider appears. The LargeButton component default color uses
`Style.effectiveSessionMenuOpacity` which resolves reactively.

- Settings schema, Style property, GeneralSubTab toggle + slider (`bc17cb04d`)

**Fix**

The icon timing race condition is eliminated. `Icon.*` references inside JS
object literals — context menu models, action metadata, session menu entries,
bar widget lists, setup wizard step indicators — were capturing their value
at parse time (before plugin icon sets registered), resulting in permanently
`undefined` icons. The fix removes all `Icon.*` from model data, replacing
them with either action-based mapping functions (`_actionIcon()` in SessionMenu)
or plain string icon names (e.g. `"noctalia"` → `"home"` for Control Center).
`NPopupContextMenu` and `NContextMenu` delegates now resolve icons via live
`switch` bindings instead of reading pre-captured model data.

47 files changed across SessionMenu, NPopupContextMenu, NContextMenu, all bar
widgets, dock menu, desktop widgets, launcher, setup wizard, media card, and
settings panels. Zero `Icon.*` references remain in any JS model data.

- SessionMenu `_actionIcon()` bridge (`9d8e9c2a7`)
- NPopupContextMenu + NContextMenu action-based mapping (`db3aec66d`, `f4d0d6b90`)
- 27 bar widget model icon removals (`3e0aadf93`)
- 11 remaining file model icon removals (`4dfed51fb`)
- Property binding Icon.* → strings + DockMenu delegate fix (`1627b5738`)
- SetupWizard + SetupCustomizeStep model icon string migration (`f6ef0764f`)
- Control Center default icon `noctalia` → `home` (`aeca865e1`)

**Fix**

Progressive QML lint hardening. Nine categories enforced and all pre-existing
violations resolved across the codebase: `alias-cycle`, `confusing-expression-statement`,
`duplicate-property-binding`, `assignment-in-condition`, `unintentional-empty-block`,
`read-only-property`, `incompatible-type`, `property-override`, and `uncreatable-type`
(false-positive suppression). These took the codebase from zero lint enforcement
to 9 categories passing clean, with `missing-property` and `missing-type` known-
suppressed at the config level (JsonObject false positives).

- `alias-cycle` (3 resolved, `1f8e90a98`)
- `confusing-expression-statement` (3 resolved, `7362da283`)
- `duplicate-property-binding` (5 resolved, `78f18a55f`)
- `assignment-in-condition` (6 resolved, `077be6374`)
- `unintentional-empty-block` (1 resolved, `e45608e2d`)
- `read-only-property` (1 resolved, `b6e63f8a3`)
- `incompatible-type` (6 real + 6 false positives, `b60179f3b`)
- `property-override` (15 resolved, `3c9529aad`)
- `uncreatable-type` false-positive suppression (`e789cefc4`)

**Fix**

Dialog FIFO hardened against races, hangs, and missing dependencies. The `mktemp`
+ `mkfifo` + `trap cleanup EXIT` pattern ensures dialog scripts don't orphan FIFO
files or hang waiting for readers that never arrive (`169c29d50`).

CLI instance discovery: replace fragile PID-file crawling with config-path
resolution (`qs -c atmosphera` lookup), eliminating stale-PID false positives that
blocked `atmosphera-session launch` after a crash (`9f89a824d`).

Duplicate `hoverHandler` IDs in `SetupCustomizeStep` and duplicate `mouseArea` IDs
in `NFilePicker` resolved (`2abd994b8`, `3b6c872a7`).

**Chore**

Devcontainer tooling built from scratch. A Dockerfile with `archlinux:base-devel`,
Qt6 declarative tools, `quickshell`, `tree-sitter`, `rustup`, `shellcheck`, and
`shfmt`. The `atmo-dev.sh` wrapper provides overlay-based write isolation and
VFS generation via `qs -p`. The pre-commit hook runs `Docker run` into the
devcontainer with `qmllint` and `qmlformat` on staged `.qml` files, using
kernel overlay to keep host changes isolated.

- Dockerfile + atmo-dev + pre-commit hook (`0f02d727b`, `5f21645b4`)
- Devcontainer devcontainer.json (`39e8802ea`)

## [0.2.0] — 2026-07-19

### 2026-07-19

**Feature**

Two new services leverage `qt6-dbusqml` (now a first-class runtime dependency) to
close long-standing security gaps. InputMethodService deactivates fcitx5 when the
lock screen is active, preventing CJK IME composition from leaking unmasked text.
LogindService subscribes to systemd-logind's `PrepareForSleep` signal on the system
bus, locking the session before *every* suspend path — including lid-close,
`systemctl suspend`, and third-party triggers — where previously only
Atmosphera-initiated suspends triggered the lock. Both services are
idempotent and degrade gracefully when their backends are absent.

- InputMethodService with lock-screen IME suppression (`acc01b51`)
- Lock on external suspend via logind PrepareForSleep (`bc467ea0`)

**Chore**

- Update flake.lock (`1505b389`)

### 2026-07-18

**Feature**

Application Shortcuts graduate from a documentation recipe to a full
first-class feature. Right-click the desktop → "Add Application Shortcut"
opens a settings dialog with app-picker and terminal-command modes. Each
shortcut supports custom parameters (docker-style list, one argument per
row), environment variables, per-widget icon selection (auto / Icons
browser / file picker), and icon colorize controls. In terminal mode,
typing a command auto-derives its icon from `hicolor/scalable/apps`.
The settings dialog now positions itself beside the widget being edited
rather than at a fixed offset, using anchor-rect awareness (right → left
→ above → below → clamp fallback) to avoid covering the widget. Widget
creation placement follows grid-snap with on-screen clamping.

- First-class Application Shortcuts: terminal registry, params, modes, icons, env, defaults (`1580e7c9`)
- Position settings dialog beside its widget (`5589494a`)

**Refactor**

NSearchableComboBox gains an opt-in stacked layout. When `stacked: true`,
the label sits above a full-width ComboBox, preventing horizontal
overflow in narrow dialogs. The root widget changes from RowLayout to
GridLayout, toggling between 2-column (default, side-by-side) and
1-column (stacked) layouts with no child duplication.

- Add opt-in stacked layout to NSearchableComboBox (`1360dab2`)

### 2026-07-17

**Feature**

The battery widget now decouples fill level from UPower state, using raw
UPower signals for honest charge/discharge predicates. This prevents false
"empty" or "full" states during transitions.

- Decouple battery fill from state, use raw UPower signals (`76cd75b0`)

**Chore**

- Update flake.lock (`7d6f7ec0`)

### 2026-07-15

**Chore**

- Update flake.lock (`8711c9a7`)

### 2026-07-13

**Chore**

- Update flake.lock (`067bdf25`)

### 2026-07-11

**Feature**

Icons on desktop app shortcuts can now be tinted toward the theme color
via a hue-replace shader (mode 3.0) — colored features of the icon shift
to the primary color while neutrals stay untouched. A reusable
`NIconColorizeEffect` wraps the shader for dock, tray, and app-shortcut
use. Global and per-widget blend-strength and hue-adjustment controls
let users dial in the effect. Desktop widgets gain per-widget content
padding for finer visual control.

- Add hue-replace icon shader (mode 3.0) and reusable NIconColorizeEffect (`983d2819`)
- Icon colorize settings (global + per-widget for AppShortcut) (`d564cf96`)
- Desktop widget content padding, global + per-widget (`2f3bee18`)

**Fix**

Several layout and signal-naming corrections shipped in rapid succession:
widget and settings-panel background opacity now track the same source,
`AtmoWidgetAppearance` gets explicit `Layout.fillWidth`, QML mode
constants comply with lowercase naming, the `DesktopMenuSubTab` column
layout is properly filled, and `AtmoWidgetAppearance` signals are renamed
to avoid conflicting with QML auto-generated property-change signals.

- Unify widget and settings panel background opacity (`00547128`)
- Fix add Layout.fillWidth to AtmoWidgetAppearance root (`41b4d869`)
- Fix lowercase NIconColorizeEffect mode constants (`5c1dc169`)
- Fix add Layout.fillWidth to DesktopMenuSubTab root ColumnLayout (`121dbc69`)
- Fix rename AtmoWidgetAppearance signals to avoid QML property conflict (`12d5940e`)

**Refactor**

Shared widget-appearance controls (blend strength, hue adjustment,
content padding) are extracted into a single `AtmoWidgetAppearance`
component, reducing duplication across widget settings pages.

- Extract widget appearance controls into shared AtmoWidgetAppearance (`241cf0fa`)

**Chore**

- Update flake.lock (`c0be18db`)

### 2026-07-10

**Feature**

Desktop context menus and click-handling give the desktop its own action
surface, independent of the bar and dock. AppShortcut gains per-shortcut
environment-variable support for wrapping launched apps in custom env blocks.

- Desktop click handling, context menu, and AppShortcut env vars (`169c29d5`)

**Fix**

NiriService now applies keyboard layout data at startup rather than
waiting for the first layout-switch event — the lock-screen layout
indicator benefits from accurate initial state.

- Apply keyboard layout data at NiriService startup (`be2f01c2`)

**Docs**

- Settings persistence and desktop click handling plans (`5d99590f`)

### 2026-07-06

**Feature**

The demo custom lockscreen is moved from `Assets/Examples/` into a proper
`Plugins/` directory alongside system plugins. Default plugins are now
bootstrapped on first run, eliminating the need for manual plugin
installation.

- Move demo-custom-lockscreen to Plugins/, bootstrap default plugins (`891f2fe4`)

**Chore**

- Update flake.lock (`5b6aa58e`)

### 2026-07-05

**Feature**

A new `DesktopAppShortcut` widget replaces the manual-JSON-editing recipe
for placing app shortcuts on the desktop. `atmosphera-lock` and
`atmosphera-settings` IPC wrappers complement the existing session CLI.
The demo lock screen is replaced with "Marina," a feature-rich lock
screen example with adjusted icon sizing and button proportions.

- Add DesktopAppShortcut for launching apps from desktop (`8eea4739`)
- Add atmosphera-lock IPC wrapper (`9e1a581e`)
- Replace demo lock screen with Marina (`2833dba3`)

**Fix**

Multiple stability fixes: plugin initialization now survives a race
during early startup, bar opacity no longer diverges from the settings
slider, the "monitors" toggle on the lock screen works correctly, the
default theme defaults to MacOS, bundled plugins are bootstrapped on
first run, and niri's blur layer rule drops the `xray` flag for correct
compositor interaction.

- Fix plugin race, bar opacity, monitors toggle, default theme to MacOS (`e7e48b3d`)
- Fix bootstrap bundled plugins on first run (`d81b88b2`)
- Fix niri: disable xray in blur layer rule (`6b048783`)
- Fix battery: return string icon names uniformly from getIcon() (`bc3e76cb`)

### 2026-07-04

**Feature**

A `lockScreenApi` object provides plugin authors a scoped API surface
for lock-screen settings, avoiding global state leakage. A new icon
override plugin remaps suspend/hibernate/login icons with SVG rendering
support in `NIcon`.

- Add lockScreenApi object for scoped plugin settings (`9da08b48`)
- Add atmosphera-icons override plugin with suspend/hibernate/login remaps (`2e7f7be1`)
- SVG-based override plugin with Icon.login + NIcon SVG rendering (`bc57fbf7`)

**Fix**

Lock command editing is now disabled when an external locker is active,
with a settings link button for convenience.

- Fix disable lock command editing for external locker, add settings link button (`90918c1d`)

**Chore**

- Update flake.lock (`a90b8f3b`)

### 2026-07-02

**Fix**

The settings panel now navigates directly to the target tab when
`openToTab` is called while the panel window is already open,
rather than ignoring the call.

- Fix navigate directly when openToTab is called while panel is open (`746fc4f7`)

### 2026-07-01

**Fix**

Lock command editing is disabled when an external locker is active, with
an explanation note in the settings UI.

- Fix disable lock command editing when external locker is active (`d3a38e16`)

**Chore**

- Update flake.lock (`d2f0d23e`)

### 2026-06-30

**Feature**

An external lock screen mode lets Atmosphera delegate locking to an
external tool (e.g. `swaylock`, `hyprlock`). Diagnostics UI and polish
improve the lock screen control flow.

- Add external lock screen mode with diagnostics and UI polish (`24db4764`)

### 2026-06-29

**Feature**

The bar gains a `'none'` position option — hides stacked widgets while
preserving the framed border for visual consistency. The Widgets and
Behavior tabs in settings are disabled when the bar position is `'none'`,
preventing configuration that would have no visible effect.

- Add 'none' position to hide bar widgets while preserving framed border (`b0903b57`)
- Disable Widgets and Behavior tabs when bar position is 'none' (`450f9ae2`)

**Fix**

NTabButton now respects its `enabled` property, blocking mouse clicks
and dimming visually when disabled.

- Fix NTabButton: respect 'enabled' property (`2b5de8ed`)

**Chore**

- Update flake.lock (`85585862`)

### 2026-06-28

**Feature**

A reference-based icon API (`Icon.<name>`) replaces stringly-typed icon
lookups, providing compile-time validation for icon names. An
`atmosphera-settings` IPC wrapper joins the CLI family.

- Reference-based icon resolution with Icon.\<name\> API (`dadcc43e`)
- Add atmosphera-settings IPC wrapper (`b8c55930`)

**Refactor**

The About settings page removes the Contributors and Supporters tabs and
adds a Changelog sub-tab, reflecting the project's new fork identity.

- Remove Contributors and Supporters tabs, add Changelog sub-tab (`84dd607c`)

### 2026-06-25

**Feature**

Wallpapers graduate to first-class plugins. Packs and pools provide
unified lifecycle management — wallpaper sources (local folders, online
packs, dynamic pools) are treated as plugins with install, enable, and
update semantics matching the icon-set and lock-screen plugin model.

- Wallpapers as plugins (packs + pools), unified plugin lifecycle (`33ce2690`)

### 2026-06-24

**Feature**

`AtmoWallpaperBackground` provides a reusable widget for rendering
wallpapers, wired into the plugin lock-screen wallpaper pipeline so
lock screens can display per-plugin wallpapers.

- AtmoWallpaperBackground widget and plugin lock-screen wallpaper pipeline (`ff4426c5`)

### 2026-06-23

**Feature**

An icon set plugin infrastructure ships with a legacy icon set as the
first consumer. New icon sets can be added as plugins with the same
install/enable/update lifecycle as wallpapers and lock screens.

- Add icon set plugin infrastructure with legacy icon set (`a1f1cd5b`)

### 2026-06-22

**Chore**

- Update flake.lock (`7addee3a`)

### 2026-06-21

**Feature**

The color scheme panel gains a local customizer with inline editing and
custom scheme persistence. Users can tweak named colors directly in the
settings UI and save their edits as a custom scheme that survives updates.

- Add color scheme customizer with local editing and custom scheme persistence (`1fe318d0`)

### 2026-06-19

**Docs**

Project documentation expands with a TODO tracker, plugin architecture
overview, and development guidelines. README links are corrected for the
fork's repository layout.

- Add TODO, plugin overview, development guideline, fix README links (`5ab29e90`)

### 2026-06-17

**Feature**

A lock screen plugin infrastructure — plugin authors can create custom
lock screen UI components with their own settings and aux-buttons
API. Includes a style selector with live-preview button and IPC handler
for programmatic lock-screen control.

- Lock screen plugin infrastructure (`fec5385d`)
- Add lock screen style selector with preview button and IPC handler (`0e87f90f`)
- Add auxButtons API for plugin settings popup and example lock screen plugin (`b9222d2c`)

**Fix**

Plugin source paths migrate to `file://` URLs for reliable cross-machine
resolution. The source dialog is polished for clarity.

- Fix migrate plugin sources to file:// URLs and polish source dialog (`bd9ab55b`)

**Chore**

- Update flake.lock (`2e89bbd8`)

### 2026-06-15

**Chore**

- Update flake.lock (`585d98ba`)

### 2026-06-13

**Feature**

A CLI-UI dialog panel driven by IPC lets shell scripts present
interactive prompts (confirmations, text input, surveys with dynamic
fields) through the Atmosphera UI layer. Bash wrappers auto-focus the
dialog on invocation.

- CLI-UI dialog panel with IPC, bash wrappers, and auto-focus (`92a68826`)
- Add survey dialog with dynamic fields (`ee923b87`)

### 2026-06-12

**Chore**

- Update flake.lock (`8261286d`)

### 2026-06-11

**Feature**

A shell switcher script enables fast switching between development and
shipping shell builds for testing.

- Add shell switcher script and development docs (`9b8b99c4`)

**Style**

All QML files receive a uniform `qmlformat` pass for consistent coding
style across the project.

- Apply qmlformat to all QML files (`c29817c7`)

**Chore**

Telemetry is removed entirely from the project. A font rename and
setup wizard restructure clean up the post-fork codebase.

- Remove telemetry, rename font, restructure setup wizard (`904e8c52`)
- Limit signature check to post-fork commits, add remote confirmation (`557c9f41`)

### 2026-06-08

**Chore**

- Update flake.lock (`902528db`)

### 2026-06-07

**Fix**

The release workflow now uses the tag body for release notes instead of
the full git log, producing concise and accurate release descriptions.

- Fix use tag body for release notes instead of full git log (`288ae87`)

**Chore**

A pre-push hook enforces signed commits and tags. `DEVELOPMENT.md`
provides canonical setup, build, test, and code standards for new
contributors.

- Add pre-push hook to enforce signed commits and tags (`ba289bcd`)
- Add DEVELOPMENT.md with setup, build, test, and code standards (`46defd32`)
