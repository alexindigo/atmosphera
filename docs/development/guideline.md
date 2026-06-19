# Project Structure & Organization

## Structure

```
Atmosphera/
├── shell.qml                   # Main shell entry point
├── Modules/                    # UI components and panels
│   ├── Bar/                    # Status bar and widgets
│   ├── DesktopWidgets/         # Desktop widgets
│   ├── Dialog/                 # Dialog panel overlays
│   ├── Dock/                   # Application dock
│   ├── Launcher/               # Application launcher
│   ├── LockScreen/             # Lock screen system
│   ├── Panels/                 # Settings, SessionMenu, etc.
│   └── ...                     # Other UI modules
├── Services/                   # Backend services
│   ├── Compositor/             # Compositor interaction
│   ├── Control/                # IPC, Hooks
│   ├── Noctalia/               # Plugin system
│   ├── UI/                     # PanelService, LockScreenRegistry
│   └── ...                     # Other services
├── Widgets/                    # Reusable UI components
│   ├── NButton.qml             # Custom button
│   ├── NTextInput.qml          # Text input
│   └── ...                     # Other widgets
├── Commons/                    # Shared utilities
│   ├── Logger.qml              # Logging
│   ├── Settings.qml            # Settings management
│   └── ...                     # Other utilities
├── Assets/                     # Static assets
│   ├── ColorScheme/            # Color schemes
│   ├── Examples/               # Example plugins
│   ├── Translations/           # i18n JSON files
│   └── ...                     # Other assets
├── Scripts/                    # Shell scripts
│   ├── bash/                   # CLI tools (atmosphera-prompt, etc.)
│   └── dev/                    # Dev tooling (formatters, patches)
├── docs/                       # Documentation
├── patches/                    # Upstream cherry-picks
└── nix/                        # Nix packaging
```

## Code Organization

| Directory | Purpose |
|-----------|---------|
| `Modules/` | UI panels and major components |
| `Services/` | Logic and backend functionality |
| `Widgets/` | Reusable UI components (`N*` prefixed) |
| `Commons/` | Shared utilities and helpers |

## Plugin Development

See [Plugin Overview](/docs/plugins/) for creating plugins.
