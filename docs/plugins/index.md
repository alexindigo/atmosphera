# Plugin Overview

Atmosphera features a powerful plugin system that allows you to extend the shell with custom functionality. Plugins are written in QML and integrate seamlessly with the shell's UI and services.

## What Can Plugins Do?

### Bar Widgets
Custom widgets for the top/bottom bar. Display system info, custom indicators, quick actions.

### Desktop Widgets
Widgets on the desktop background. Positioned and scaled by the user in edit mode.

### Control Center Widgets
Quick action buttons in the Control Center panel.

### Launcher Providers
Custom search sources and command handlers for the launcher.

### Panels
Full-screen overlay panels, opened from bar widgets or triggered programmatically.

### Lock Screen Components
Replace the lock screen UI entirely. Provide a custom visual lock screen that integrates with the built-in PAM authentication.

### Settings UI
Configuration interface for your plugin, integrated with the settings panel.

### Main Component
Background logic and IPC handler (for external commands and scripts).

## Plugin Architecture

```
your-plugin/
├── manifest.json              # Plugin metadata (required)
├── Main.qml                   # Background logic with IPC (optional)
├── BarWidget.qml              # Bar widget (optional)
├── DesktopWidget.qml          # Desktop widget (optional)
├── ControlCenterWidget.qml    # Control center button (optional)
├── LauncherProvider.qml       # Launcher search provider (optional)
├── LockScreenView.qml         # Lock screen UI (optional)
├── Panel.qml                  # Panel overlay (optional)
├── Settings.qml               # Settings UI (optional)
├── i18n/                      # Translations (optional)
│   ├── en.json
│   └── es.json
└── README.md
```

## Plugin Lifecycle

1. **Installation** — Plugin is downloaded to `~/.config/atmosphera/plugins/`
2. **Registration** — PluginRegistry scans and validates the manifest
3. **Enabling** — User enables the plugin in settings
4. **Loading** — PluginService loads components and injects the Plugin API
5. **Running** — Components receive `pluginApi` property
6. **Settings** — User can configure through the settings UI
7. **Unloading** — Cleanly unloaded when disabled
8. **Uninstallation** — Plugin folder removed from disk

## Plugin API

Every plugin component receives a `pluginApi` object. A bar, control-center or
desktop widget receives the api of its **instance** (see [Instances](#instances));
Main, launcher providers and the plugin settings page receive the plugin api.

### What each entry point receives

Every entry point receives `pluginApi`. The table lists the other values the
shell hands over. The names are the `entryPoints` keys of the manifest; the
same table is the source of truth in `Services/Plugins/PluginContract.js`.

| Entry point | Context names (besides `pluginApi`) |
|---|---|
| `main` | none |
| `barWidget` | `screen`, `widgetId`, `section`, `sectionWidgetIndex`, `sectionWidgetsCount` |
| `controlCenterWidget` | `screen`, `widgetId`, `section`, `sectionWidgetIndex`, `sectionWidgetsCount`, `widgetSettings` |
| `desktopWidget` | `screen`, `widgetData`, `widgetIndex` |
| `panel` | `screen` |
| `settings` | none |
| `desktopWidgetSettings` | `widgetSettings` |
| `launcherProvider` | none |

**Delivery rule.** A context name reaches the component in one of three ways:

- If the entry file declares the name on its root object (`property <type> <name>`,
  `required property ...`, `readonly property ...` or `property alias <name>`), the
  shell sets it at creation, before the first binding is evaluated. Declare a name
  on the root to use it from the start.
- If the name is inherited from a base type of the root (for example a root that
  extends a type with a `screen` property), it is set right after creation and kept
  in sync with the shell's value.
- A name the root neither declares nor inherits is never set, and nothing is
  logged. Do not reference such a name without declaring it.

### Members of `pluginApi`

**Identity and manifest**
- **`pluginId`** — Unique plugin identifier
- **`pluginDir`** — Plugin directory path
- **`manifest`** — Plugin manifest data

**Settings**
- **`pluginSettings`** — Plugin settings object (read/write, then call `saveSettings()`).
  In an instance api this is the plugin settings with the instance's overrides on top.
- **`saveSettings()`** — Persist `pluginSettings` to disk

**Shared state** (see [Shared state](#shared-state))
- **`state`** — Plugin-wide object, the same for every instance
- **`stateLoaded`** — `true` once the state file has been read
- **`saveState()`** — Persist `state` to disk

**Entry point references** (set by the shell after load; treat as read-only)
- **`mainInstance`**, **`barWidget`**, **`desktopWidget`**, **`controlCenterWidget`**, **`launcherProvider`**

**Panels**
- **`panelOpenScreen`** — The screen this api's panel is open on, `null` when closed.
  Set before the panel content loads.
- **`openPanel(screen, buttonItem)`**, **`togglePanel(screen, buttonItem)`**,
  **`closePanel(screen)`** — Control this plugin's panel. In an instance api, open and
  toggle use that instance's api for the panel.

**Launcher**
- **`openLauncher(screen)`**, **`closeLauncher(screen)`**, **`toggleLauncher(screen)`**

**Translations**
- **`tr(key, interpolations)`**, **`trp(key, count, interpolations)`**, **`hasTranslation(key)`**
- **`currentLanguage`** — Active language code
- **`translationVersion`** — Increments when translations change; bindings that use `tr` should depend on it

**Other**
- **`getConfig(callback)`** — Read the plugin's layered config (shipped defaults plus the user override)
- **`withCurrentScreen(callback)`** — Calls `callback` with the screen under the cursor
- **`pluginTranslations`**, **`pluginFallbackTranslations`**, **`ipcHandlers`** — Shell-internal storage; do not write to them

### Lock Screen API
Lock screen components receive additional properties from the shell:
- **`lockContext`** — Authentication context (PAM). Provides `passwordText`, `tryUnlock()`.
- **`screen`** — The screen the lock surface is on (for wallpaper)
- **`lockScreenApi`** — Object with the lock screen settings the shell passes:
  `compactMode`, `animationsEnabled`, `clockStyle`, `clockFormat`, `passwordChars`,
  `showSessionButtons`, `showHibernate`, `showMediaControls`, `showCountdown`,
  `countdownDuration`, `lockBlur`, `lockTint`. Read them as `lockScreenApi.compactMode`, etc.
- **`pluginApi`** — The plugin API (only for non-default plugins)

### Services
- **`qs.Commons`** — `Settings`, `I18n`, `Logger`, `Style`, `AtmoColor`
- **`qs.Services.UI`** — `ToastService`, `PanelService`, `LockScreenRegistry`
- **`qs.Services.System`** — `AudioService`, `BatteryService`, `NetworkService`
- **`qs.Widgets`** — `NButton`, `NIcon`, `NText`, `NTextInput`, etc.

### Data-driven launcher providers

An asynchronous `launcherProvider` can publish `signal resultsChanged` when
its data or readiness changes. The launcher observes this signal through the
same registration path as built-in providers and reprojects the current query,
preserving the selected result by identity. Publish completion even when the
query is unchanged. `getResults(query)` reads current data; it does not start
loads or freeze a completed query. Show a loading placeholder only while no
usable records exist; cached results remain usable during a background refresh.

Provider instances persist across launcher opens, while the live launcher and
its signal subscriptions do not. A provider can finish loading with no launcher
attached; its cached data is used on the next open. Existing providers that
call `launcher.updateResults()` remain supported.

## Instances

- A **plugin** is the code plus its plugin-level settings and shared state. It is
  the class.
- An **instance** is a plugin plus a configuration. Placing a plugin's bar widget,
  control-center shortcut or desktop widget creates an instance. The same plugin
  can have any number of instances, and an instance need not be unique.
- An instance keeps only the values it overrides, under `instanceSettings` in its
  entry in the widget list (`Settings.data`). Nothing else is stored per instance.
- **Monitors.** One entry in the shared bar list is one instance, drawn on every
  monitor that uses that list. A monitor with its own widget list has its own
  instances.
- **Settings.** A placed widget's `pluginSettings` is the plugin settings with the
  instance's overrides on top. A change to the plugin settings reaches every instance
  that does not override that value.
- **Saving.** `saveSettings()` from a placed widget stores only the values that differ
  from the plugin settings, in that widget's instance. It never changes the plugin
  settings. `resetSettings()` on the instance api removes all of its overrides.
- **Settings page.** Settings → Plugins edits the plugin level. The gear on a plugin
  entry in the bar, control-center or desktop widget settings opens the same settings
  page for that instance, with a "Reset to plugin settings" button.
- **Panels.** `openPanel()` and `togglePanel()` on a widget's `pluginApi` open the panel
  with that instance's api, so the panel sees that instance's settings.

## Shared state

Use `pluginSettings` for values the user configures. Use `state` for values the
plugin records for itself: caches, last-known values, counters.

- `state` is a plain object, shared by the plugin and all its instances.
- It is stored as `state.json` in `plugins/<plugin id>/` under the state directory:
  `$ATMOSPHERA_STATE_DIR`, else `$XDG_STATE_HOME/atmosphera/`, else
  `~/.local/state/atmosphera/`. Plugin settings are stored separately, in
  `~/.config/atmosphera/settings/plugins/<plugin id>.json`.
- The state is loaded before any entry point is created. A missing file starts
  empty. A corrupt file is kept as `state.json.corrupt-<time>` and the state starts
  empty.
- Change `state` and call `saveState()`. The save is atomic (temporary file, then
  rename) and it reassigns `state` so that bindings in instances re-evaluate. Store
  only JSON-serializable values.

## Example Plugin

A complete example lock screen plugin is available at
[`builtin/plugins/demo-custom-lockscreen/`](https://github.com/alexindigo/atmosphera/tree/main/builtin/plugins/demo-custom-lockscreen).
