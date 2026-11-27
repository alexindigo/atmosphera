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
desktop widget receives the runtime API of its **instance** (see
[Instances](#instances)); Main and launcher providers use the plugin runtime API.
A generic settings page receives a distinct selected editor API: plugin scope
from Settings -> Plugins, instance scope from a placed widget's Settings route.

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

### Members of the runtime `pluginApi`

**Identity and manifest**
- **`pluginId`** — Unique plugin identifier
- **`pluginDir`** — Plugin directory path
- **`manifest`** — Plugin manifest data

**Settings**
- **`pluginSettings`** — Plugin settings object (read/write, then call `saveSettings()`).
  In an instance api this is the plugin settings with the instance's overrides on top.
- **`saveSettings()`** — Persist `pluginSettings` to disk

### Generic settings page API

The generic page has `apiRole: "settings-editor"` and immutable `scopeKind`
(`plugin` or `instance`). Its `pluginSettings`/`initialSettings` are read-only
presentation copies, never live writers. Obtain `pluginApi.field("message")`
for a declared configuration leaf; read its `value`, and call `set(value)` only
from the control's explicit user event or committed input. Wrap the control in
`NPluginSettingsField` with that handle for inherited/override/pending state and
Reset. Compound preferences remain atomic top-level leaves.

Page `saveSettings()` commits buffered field intents only. The injected
`pluginApi.saveSettings(callback)` registers completion; it never publishes or
collects an effective snapshot. The shell session owns Apply and persistence.
Only `saved`/`nothing_to_save` plus `refreshState: current` acknowledge success;
failed/stale results retain local work. `settingsCompleted` precedes callbacks.

Field Reset stages removal to reveal the inherited/native lower level. Whole
instance configuration Reset removes declared configuration overrides, retaining
legacy content/operational/opaque siblings. Shared content commands may use
`contentField(key)` only in plugin scope; ordinary configuration Apply never
collects content. Explicit state/config/application actions retain their own
owners and are not undone by Cancel. Runtime API injection is rejected before
generic page construction. External pages must adopt the field contract.

See [editor ownership](../development/plugin-settings-editors.md) and
[field capabilities](../development/plugin-settings-field-capabilities.md).

### Other runtime API members

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

### Images

Show images that can come from outside your plugin (user files, downloads,
covers, avatars, thumbnails) with the shell's image widgets instead of
`Image`/`AnimatedImage`/`IconImage`: `NImage`, `NImageRounded`, `NImageIcon`,
and `NImageText` for rich text or Markdown that may contain images. They
render natively when Qt can (WebP needs `qt6-imageformats`) and otherwise
show a validated PNG or animated GIF decoded by ImageMagick/FFmpeg; a failure
is labelled, not silent. Do not run your own `magick`/`ffmpeg` conversions:
ask `ImageCacheService` for thumbnails. `Text` that shows data sets
`textFormat: Text.PlainText`. Fixed images shipped with the plugin may use
`Image` directly. The shell's image boundary check lists every other use.
Details: [image sources](../development/image-sources.md).

### Declaring actions

An optional manifest `actions` list describes user-facing operations. Loaded
plugins can contribute actions from their Main `IpcHandler` or from their panel
entry point. Unavailable actions are absent, never disabled.

```json
"actions": [{
  "id": "toggle",
  "label": "Clipboard panel",
  "description": "Toggle the clipboard plugin panel.",
  "icon": "clipboard",
  "command": "atmosphera ipc plugin:clipboard toggle"
}]
```

| Field | Contract |
|---|---|
| `id` | Lowercase letter followed by lowercase letters, digits or hyphens; unique within the source |
| `label`, `description` | Non-empty single-line strings |
| `icon` | Key from the shell's built-in icon set |
| `command` | For a Main action: exactly `atmosphera ipc <target> <function>`, safe words separated by single spaces |
| `arguments` | For a Main action: optional ordered list of typed arguments, each with `name`, `label`, `type` and a valid `default` |
| `panel` | For a panel action: `open`, `toggle` or `close`; requires `entryPoints.panel` and replaces both `command` and `arguments` |

Argument names start with a lowercase letter and contain only letters/digits.
Types are `choice` (non-empty unique `{value, label}` choices), `number` (integer,
optional integer `min`/`max` and string `unit`) and `text` (non-empty single line).
Unknown keys are rejected, including on arguments and choices. Every argument
needs a valid default; placeholders are not commands. Plugin actions do not set
`group`, `requiresPlugin` or `compositor`: those are core-catalog fields only.

The compatibility gate checks icons, duplicate IDs and commands. It checks
Main actions against the plugin's real Main entry point for target/function,
arity and supported parameter types. Parameters require an explicit `string` type; `int` is also
accepted for number arguments. Untyped and `var` parameters are not registered
by Quickshell IPC. A handler may have at most ten parameters, and its return type
must also be IPC-compatible (no annotation, `void`, `var`, `string`, `int`, `bool`,
`real` or `color`). Do not declare helpers merely because they are callable.

A panel-only plugin does not need to add a Main entry point:

```json
"entryPoints": {"panel": "Panel.qml"},
"actions": [{
  "id": "toggle",
  "label": "My panel",
  "description": "Toggle my panel.",
  "icon": "terminal",
  "panel": "toggle"
}]
```

The picker saves `atmosphera ipc plugin togglePanel <plugin-key>` (or
`openPanel`/`closePanel`) using the installed plugin's key. A literal hot-corner
command uses the corner's output; a CLI invocation uses the current output.
Set `minAtmospheraVersion` to the first released shell that supports panel
actions, or to a later release if the plugin needs other features.

Existing `atmosphera ipc niriWindowsMap open|toggle|close` spellings remain
accepted by the CLI and the hot-corner command reader via
`Assets/Actions/legacy-panel-commands.tsv`. The same table preserves picker
actions for matching installed plugin versions that have a panel but omit
`actions`; a manifest that declares actions always wins. Retire the compatibility
rows only in an announced breaking shell release after their replacement has
shipped. An updated plugin manifest alone is not a removal trigger: external
bindings may still use the old command.

### Using the action registry

Import `qs.Services.Actions` and require `minAtmospheraVersion: "0.10.0"`.
`ActionRegistry.ready` reports core-catalog loading; `actions` contains plain
objects with `key`, `section`, `group`, `label`, `description`, `icon`, `command`
and `arguments`. Plugin groups use their manifest names; keys are qualified by
the installed plugin key. Core groups retain catalog order. The registry's
`revision` increments when plugins load, unload or reload.

`compose(action, values)` takes values keyed by argument name, using defaults for
missing values, and returns a safely quoted command (or `""` for an invalid
value). `match(command)` returns `{action, values}` only when that command is
exactly reproduced by composition; otherwise it returns null. Use
`displayLabel(action, values)` for the action and chosen argument labels. Keep
the literal stored command visible: recognition never rewrites custom input.

### Data-driven launcher providers

An asynchronous `launcherProvider` can publish `signal resultsChanged` when
its data or readiness changes. The launcher observes this signal through the
same registration path as built-in providers and reprojects the current query,
preserving the selected result by identity. Publish completion even when the
query is unchanged. `getResults(query)` reads current data; it does not start
loads or freeze a completed query. Show a loading placeholder only while no
usable records exist; cached results remain usable during a background refresh.

A refresh keeps the result row of every item whose identity is unchanged and
only adds, moves and removes the others. The identity is the provider plus the
first of `windowId`, `clipboardId`, `appId`, `usageKey`, `id` or `name` (the
same rule that preserves the selection), so give rows a stable `id`. Rank or
score never takes part. `prepareItem(item)` runs once while an item is shown.
To reload one item's image from `getImageUrl(item)`, emit
`signal itemImageChanged(var identity)` with that item's identity value; only
its rows react. A provider-wide `imageRevision` property still re-reads every
row. `getResults(query)` runs on every keystroke: derive anything costly from
your data when the data changes, not per query.

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
- **Settings page.** Settings -> Plugins edits the plugin level. The gear on a plugin
  entry in the bar, control-center or desktop widget settings opens the same settings
  page for that captured instance. Runtime desktop Settings selects the same owner.
  Only explicit field intents become sparse overrides. "Reset instance
  configuration" removes declared configuration overrides, not legacy content.
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

## Retired plugins

- `hot-corners` is built into the shell from 0.10.0 (Settings -> General -> Hot
  corners). On the first start of 0.10.0, plugins registry migration v6 imports
  commands from enabled installs into empty shell corners only, backs the plugin
  up under `~/.config/atmosphera/backups/plugins-v6-<time>/` and uninstalls it.
  Commands from disabled installs or for already configured shell corners remain
  available in that backup. Failed reads, backup or settings saves leave the
  migration pending and the plugin installed for a later start.

## Example Plugin

A complete example lock screen plugin is available at
[`builtin/plugins/demo-custom-lockscreen/`](https://github.com/alexindigo/atmosphera/tree/main/builtin/plugins/demo-custom-lockscreen).
