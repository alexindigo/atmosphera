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

Every plugin component receives a `pluginApi` object:

### Core Properties
- **`pluginId`** — Unique plugin identifier
- **`pluginDir`** — Plugin directory path
- **`pluginSettings`** — User settings object (read/write)
- **`manifest`** — Plugin manifest data
- **`saveSettings()`** — Persist settings to disk

### Lock Screen API
Lock screen components receive additional properties from the shell:
- **`lockContext`** — Authentication context (PAM). Provides `passwordText`, `tryUnlock()`.
- **`screen`** — The screen the lock surface is on (for wallpaper)
- **`compactMode`** — Whether compact lock screen is enabled
- **`animationsEnabled`** — Whether animations are enabled
- **`pluginApi`** — The plugin API (only for non-default plugins)

### Services
- **`qs.Commons`** — `Settings`, `I18n`, `Logger`, `Style`, `Color`
- **`qs.Services.UI`** — `ToastService`, `PanelService`, `LockScreenRegistry`
- **`qs.Services.System`** — `AudioService`, `BatteryService`, `NetworkService`
- **`qs.Widgets`** — `NButton`, `NIcon`, `NText`, `NTextInput`, etc.

## Example Plugin

A complete example lock screen plugin is available at
[`Assets/Examples/demo-custom-lockscreen/`](https://github.com/alexindigo/atmosphera/tree/main/Assets/Examples/demo-custom-lockscreen).
