# D-Bus Compatibility Layer

Bridges atmosphera's internal state to D-Bus interfaces that apps/widgets expect from other desktop environments — filling gaps on systems where no DE is running.

## How it works

Each compat service probes its D-Bus name at startup. If the name is free (no DE registered it), it claims it and translates between the DE's protocol and atmosphera's internal state. If the name is occupied (GNOME/KDE is running), it stays silent and lets the DE handle it — no conflicts.

```
App/widget queries          Compat service (if name is free)
    │                                │
    ├─ org.gnome.X                  ─┤  translate ↔ atmosphera's state
    ├─ org.kde.Y                    ─┤
    ├─ org.freedesktop.Z            ─┤
```

## Added value

- Apps that hardcode `org.gnome.ScreenSaver` work on Niri without GNOME.
- Widgets that expect `org.kde.keyboard` see keyboard layout changes.
- Everything falls through gracefully if the real DE is present.

## Interface list

| Interface | D-Bus name | Purpose | Status |
|-----------|-----------|---------|--------|
| Screensaver | `org.freedesktop.ScreenSaver` | Inhibit/UnInhibit idle | Planned |
| Input layout | `org.gnome.desktop.input-sources` | Current keyboard layout | Planned |
| Input layout | `org.kde.keyboard` | Current keyboard layout | Planned |
| Color scheme | `org.gnome.desktop.interface` | `color-scheme` via gsettings compat | Planned |

## Adding a new compat service

1. Create `Services/Compat/<Name>.qml`
2. On `Component.onCompleted`, try to register the D-Bus name
3. If registration succeeds, connect to atmosphera's internal signals and expose them via the DE's protocol
4. If registration fails (name occupied), log and stay idle
