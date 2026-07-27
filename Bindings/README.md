# Atmosphera Bindings

Environment-specific keyboard-shortcut configurations shipped with Atmosphera.

An *environment* is a coherent shortcut style (e.g. macOS) that spans multiple layers
of the input stack. Each environment lives in `environments/<name>/` and is
self-contained.

## Layout

```
Bindings/
├── close-tab-or-window        # Shared niri helper (env-agnostic)
├── environments/
│   └── macos/                 # macOS-style shortcuts
│       ├── keyd/              # Hardware-level modifier swap (root)
│       ├── niri/              # Compositor keybinds
│       ├── xremap/            # User-level key remapping
│       └── zed/               # Editor keymap
└── docs/                      # Reference: macOS shortcuts, modifier mapping, keyd rationale
```

## Layered architecture

```
Physical keyboard
    → keyd            (Alt↔Super hardware swap; needs root)
    → xremap          (text nav, word nav, terminal fixes; user)
    → niri            (WM binds; user)
    → apps            (Zed and others; user)
```

## Selecting an environment

The `bindings.environment` setting controls which environment is applied. Default is
`"none"`. Change via the setup wizard on first run, or in Settings → General → Shortcuts.

## Adding a new environment

1. Create `environments/<name>/` with the same shape as `environments/macos/`.
2. Extend the settings enum in `Commons/Settings.qml`.
3. Add a case in `Scripts/bash/atmosphera-bindings-apply`.
4. Add a wizard/settings choice in `SetupBindingsStep.qml` and `ShortcutsSubTab.qml`.
