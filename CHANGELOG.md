# Changelog

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
