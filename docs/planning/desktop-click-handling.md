# Desktop Click Handling & Context Menu

**Date:** 2026-07-09
**Status:** In progress

---

## Overview

Enable right-click on desktop empty space to show a context menu with actions like "Add Application Shortcut" (at click position), "Change Wallpaper", "Display Settings", and "Toggle Edit Mode". Built in three phases:

1. Raw click handler exposed via the Hooks system (shell command customization)
2. Default context menu on right-click with built-in actions
3. Settings panel to customize which items appear in the menu

---

## Phase 1 — Raw click handler + Hooks exposure

### Data model

**`Commons/Settings.qml`** — three new hook properties inside `hooks` JsonObject:

```
property string desktopLeftClick: ""
property string desktopRightClick: ""
property string desktopMiddleClick: ""
```

Each accepts a shell command. `$1` = screen name, `$2` = X coordinate, `$3` = Y coordinate.

### Service dispatch

**`Services/Control/HooksService.qml`** — three new public dispatch functions following the existing detached pattern:

- `executeDesktopLeftClickHook(screenName, x, y)`
- `executeDesktopRightClickHook(screenName, x, y)`
- `executeDesktopMiddleClickHook(screenName, x, y)`

Each: checks `Settings.data.hooks.enabled` → checks script non-empty → replaces `$1/$2/$3` → runs `Quickshell.execDetached(["sh", "-lc", command])`.

### Input plumbing

**`Modules/DesktopWidgets/DesktopWidgets.qml`** — 3 changes:

1. **Mask**: Change `mask: DesktopWidgetRegistry.editMode ? null : widgetsMask` to `mask: null` (always receive full input). Remove the `widgetsMask` Region, `_maskRegions` array, `maskRegionComponent`, and the onLoaded/onItemChanged mask-region wiring — dead code now.

2. **Desktop MouseArea**: Inside `widgetsContainer`, at `z: -2` (behind the grid overlay at `z: -1` and widget loaders), `acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton`. On click, dispatches to the appropriate hook via screen coordinates.

3. **Widget Loader cleanup**: Remove `_maskRegion` property, `maskRegionComponent`, and push/splice logic from widget Loaders. Widget MouseAreas handle their own clicks by z-order.

### Hook settings UI

**`Modules/Panels/Settings/Tabs/Hooks/HooksListSubTab.qml`** — add 3 new `HookRow` entries for left/right/middle click hooks.

### Translations

**`Assets/Translations/en.json`** — add 9 keys (label + description + placeholder × 3) under `panels.hooks`.

### Search index

**`Assets/settings-search-index.json`** — add entries for the 3 new hooks.

---

## Phase 2 — Default context menu on right-click

### Data model

**`Commons/Settings.qml`** — add to the `desktopWidgets` JsonObject (or new `desktop` object):

```
property JsonObject desktopContextMenu: JsonObject {
    property bool enabled: true
    property list<var> items: [
        { "id": "add-app-shortcut" },
        { "id": "divider" },
        { "id": "change-wallpaper" },
        { "id": "display-settings" },
        { "id": "toggle-edit-mode" }
    ]
}
```

### Context menu dispatch

**`DesktopWidgets.qml`** — add `buildDesktopContextMenuModel()` and `showDesktopContextMenu(x, y)` functions. On right-click, after hook fires, show the context menu via `PopupMenuWindow.showDynamicContextMenu()`.

Actions:
- `add-app-shortcut` — creates AppShortcut widget at click position
- `change-wallpaper` — opens wallpaper settings
- `display-settings` — opens display panel
- `toggle-edit-mode` — toggles `DesktopWidgetRegistry.editMode`

### `addWidgetToCurrentScreen` enhancement

Add optional `x, y` parameters to place the widget at click position.

---

## Phase 3 — Settings panel to customize context menu

### Settings UI

**New file: `Modules/Panels/Settings/DesktopWidgets/DesktopMenuSubTab.qml`** — toggle list of available context menu items, with drag-reorder support (NSectionEditor pattern). Items can be enabled/disabled and reordered.

Divider between tools and settings groups handled automatically.

**`Modules/Panels/Settings/Tabs/DesktopWidgetsTab.qml`** — add DesktopMenuSubTab as a section/subtab.

### Translations

Keys for menu item labels, section titles, descriptions.

### Search index

Entries for desktop context menu settings.

---

## Files modified/created per phase

| File | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| `DesktopWidgets.qml` | mask→null, add click area, remove mask wiring | add context menu model+handler, enhance addWidget | — |
| `HooksService.qml` | 3 new dispatch functions | — | — |
| `Settings.qml` | 3 new hook props | desktopContextMenu object | — |
| `HooksListSubTab.qml` | 3 new HookRows | — | — |
| `DesktopMenuSubTab.qml` | — | — | **new file** |
| `DesktopWidgetsTab.qml` | — | — | add DesktopMenuSubTab |
| `en.json` | 9 hook keys | 5+ menu item keys | 5+ settings UI keys |
| `settings-search-index.json` | 3 entries | 2 entries | 1 entry |
