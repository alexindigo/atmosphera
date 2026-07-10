# Settings State Persistence & Kirigami Evaluation

**Date:** 2026-07-09  
**Status:** Future consideration — not yet implemented

---

## Context

During a discussion about what would make the Settings panel less annoying to use, the idea of adopting **KDE Kirigami** (a convergent QML UI framework) came up as a potential solution. After investigation, we concluded:

1. **Kirigami is not the right tool** for this shell — it's architecturally aimed at `ApplicationWindow`-style apps, not wlr-layer-shell surfaces. Pulling it in would add KF6 runtime dependencies and risk theme collisions with the existing `N*` widget system, for minimal gain.
2. The **real pain point** is that the Settings panel (both window mode and panel mode) **resets its position (tab, subtab, scroll position) every time it's closed and reopened**.

This document captures the full plan for solving that state-persistence problem.

---

## Kirigami Evaluation (for posterity)

### What was considered

Using `org.kde.kirigami` as a UI framework for the Settings panel, to get:
- `Kirigami.PageRow` / `PageStack` for navigation
- `Kirigami.FormLayout` for settings forms
- `Kirigami.Theme` for styling
- Theme-aware icon rendering

### Why it was ruled out

| Concern | Detail |
|---------|--------|
| **Runtime mismatch** | Kirigami centers on `Kirigami.ApplicationWindow`; Atmosphera uses `PanelWindow` + `WlrLayershell` for shell surfaces. Core Kirigami APIs (PageRow, drawers, global toolbar) don't work inside layer-shell surfaces. |
| **Dependency footprint** | Adding Kirigami means shipping KF6 Kirigami + KCoreAddons + KIconThemes + `qqc2-desktop-style` at runtime. For the Nix flake: adding `kdePackages.kirigami`, wrapping Quickshell with correct `QML2_IMPORT_PATH`/`QT_PLUGIN_PATH`, and ensuring Qt version parity with `noctalia-qs`. |
| **Theme collision** | Kirigami uses `Kirigami.Theme` driven by QPA color scheme + QQC2 style. Atmosphera has its own theme system (`Commons/Color.qml`, `Commons/Style.qml`, `Services/Theming`). Using both together would either clash visually or require a custom theme bridge. |
| **Widget duplication** | `Kirigami.Icon` is the most appealing piece — but Atmosphera already has `NIcon.qml`, `Icon.qml`, `ThemeIcons.qml` doing the same thing. |
| **Low ROI** | The parts of Kirigami that *could* work inside a `PanelWindow` (Icon, Units, FormLayout, Card) mostly replicate existing infrastructure. |

### When Kirigami *might* still be considered

- If a future Settings panel becomes a **standalone application** (separate binary, real `ApplicationWindow` launched via `Quickshell.execDetached`). That window could legitimately use Kirigami PageRow/FormLayout without the layer-shell constraints.
- If you want the icon-theme fallback from `Kirigami.Icon` badly enough to ship KF6 for it.

---

## Settings State-Persistence Plan

### Problem

Both Settings surfaces lose their position on close/reopen:

**Window mode** (`SettingsPanelWindow.qml`):
- A `FloatingWindow` that stays alive when hidden, but `onVisibleChanged` resets `isInitialized = false` on hide.
- `navigateTo()` always re-initializes and jumps to `requestedTab` (defaults to `General`).
- `SettingsPanelService.openWindow()` / `toggleWindow()` always passes an explicit tab.

**Panel mode** (`SettingsPanel.qml` via `SmartPanel`):
- Closing the layer-shell surface tears down the content.
- `onOpened` unconditionally calls `_settingsContent.initialize()` and applies `requestedTab`.

**Common** (`SettingsContent.qml`):
- `currentTabIndex`, `_pendingSubTab`, and per-tab scroll position live only in the QML tree. Nothing is persisted to `SettingsPanelService` or `Settings.data`.

### Goals

- Opening Settings with no explicit tab (bare toggle/keybind) should restore **last tab + subtab + scroll position**.
- Opening Settings via an **explicit request** (e.g. "Open Bluetooth settings" from tray) should **still jump to that target**.
- Work in both **window mode** and **panel mode**.
- State survives **close/reopen for the shell session** (in-memory). Could later be extended to survive shell restarts via `Settings.data` if desired.

### Proposed Implementation

#### 1. `Services/UI/SettingsPanelService.qml` — add state store

```qml
property int lastTab: 0
property int lastSubTab: -1
// keyed by tabId: { subTab: int, scrollPos: real }
property var scrollPositions: ({})

function rememberPosition(tab, subTab, scrollPos) {
  lastTab = tab;
  lastSubTab = subTab;
  scrollPositions[tab] = { subTab, scrollPos };
}

// Returns { tab, subTab, scrollPos }
// explicitTab/subTab override the stored state if provided.
function getRestoreTarget(explicitTab, explicitSubTab) {
  const tab = (explicitTab !== undefined && explicitTab >= 0) ? explicitTab : lastTab;
  const stored = scrollPositions[tab] || {};
  return {
    tab: tab,
    subTab: (explicitSubTab !== undefined && explicitSubTab >= 0) ? explicitSubTab : (stored.subTab ?? -1),
    scrollPos: stored.scrollPos ?? 0,
  };
}
```

#### 2. `SettingsContent.qml` — emit position updates

- Call `SettingsPanelService.rememberPosition(...)` whenever:
  - `currentTabIndex` changes (debounced)
  - `setSubTabIndex` succeeds
  - The active `ScrollBar.vertical.position` changes (throttled, e.g. 200ms)
- Add `restoreScrollTo(pos)` — used after the tab's content loads, analogous to the pending-subtab flow at `:1275`.

#### 3. `SettingsPanelWindow.qml` — remove state reset, use restore path

- Delete `isInitialized = false` in `onVisibleChanged` (`:66`).
- `navigateTo(tab, subTab)`:
  - If no explicit tab passed (bare toggle), call `SettingsPanelService.getRestoreTarget()` and navigate there.
  - If explicit tab passed, use it directly (existing behavior).
  - After content loads, restore scrollpos for the target tab.
- Add a `restoreWindow()` entrypoint for plain toggles (or let `openWindow` drop its `requestedTab` default so `undefined` flows through).

#### 4. `SettingsPanel.qml` — apply restore in `onOpened`

- If `requestedEntry` is null and `requestedTab` is default (General), assume a bare open → consult `SettingsPanelService.getRestoreTarget()` before `initialize()`.
- `openToTab` still forwards explicit tab; bare `toggle()` from bar without a tab restores last.

#### 5. `shell.qml` / bar keybinds — audit callsites

- The "open settings" keybind/button with **no specific tab argument** should go through the restore path.
- Dedicated entries like "Settings → Bluetooth" should still force Bluetooth.

### Open Questions / Decisions (for when implementation begins)

1. **Scope — which modes should remember state?**
   - (a) Only window mode (simplest)
   - (b) Both window and panel mode ← recommended
2. **Where to store position — memory or disk?**
   - (a) In-memory on `SettingsPanelService` — survives close/reopen, resets on shell restart ← recommended
   - (b) Persisted to `Settings.data.ui.settingsLast{Tab,SubTab,Scroll}` — survives shell restart
   - (c) Hybrid: tab+subtab to disk, scroll to memory only
3. **When caller explicitly requests a tab — what wins?**
   - Explicit always wins. Only bare toggle restores last position. ← recommended
4. **Scroll position tracking — per-tab or global?**
   - (a) Tab + subtab only (covers ~80% of annoyance)
   - (b) Per-tab scroll positions stored in a map ← recommended
5. **Panel mode — keep current teardown behavior or rework the surface lifecycle?**
   - (a) Keep teardown, store/restore position via service ← recommended
   - (b) Rework so SettingsContent stays alive even when panel is hidden (riskier)
