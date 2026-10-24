# Launcher keyboard ownership

The launcher uses one `NKeyOwner` and one table in `LauncherCore` for every
provider, layout and host. The search is the only focus holder. Other controls
remain pointer-operated; if one takes focus, the owner restores the editor
synchronously. Providers receive result activation and removal callbacks, not
raw keyboard events. A provider requiring its own focused editor needs a
separate interaction design.

| # | Key | Meaning |
|---|---|---|
| 1 | Characters, Space, input-method commits | Type in search |
| 2 | Backspace, Delete, Left/Right, Home/End | Native text editing and cursor movement |
| 3 | Shift with the editing keys; Ctrl+Left/Right/Backspace/Delete | Native selection and word editing |
| 4 | Ctrl+A/C/X/V/Z and native redo | Select all, copy, cut, paste, undo and redo |
| 5 | Escape | Close |
| 6 | Return or keypad Enter | Activate selected result |
| 7 | Up/Down | Previous/next result, or one row in a grid |
| 8 | Page Up/Down | One visible page, clamped at the ends |
| 9 | Ctrl+Home/End | First/last result |
| 10 | Tab/Shift+Tab | Next/previous result, sideways in a grid |
| 11 | Ctrl+Tab/Ctrl+Shift+Tab | Next/previous category |
| 12 | Shift+Delete | Remove selected result where supported (clipboard) |

Existing configurable command bindings override editing meanings. Left/Right
navigation settings remain available to other panels but are not used by the
launcher. Settings migration 62 moves only the old Remove default (`["Del"]`)
to `["Shift+Del"]`; custom and intentionally empty bindings are preserved.
Notification history's existing Delete behavior is unchanged.

`NKeyOwner` receives the scope, native TextInput, key-string function and table
as inputs. `Keys.BeforeItem` executes commands before native editing, and
`shortcutOverride` reserves only table commands; editing keeps Qt's native
shortcut-override and input-method filtering path. Unbound non-editing keys
are consumed as no-op commands, so they cannot invoke a different surface.
Preedit bypasses command dispatch; the input method owns its commit/cancel.
No focus timers or deferred refocus are involved. Result loading may be
deferred but never gates typing or command handling.

Keys delivered to another application before the compositor transfers keyboard
focus (the known approximately 40 ms shortcut handoff) cannot be recovered.

With `QT_IM_MODULE=fcitx`, an upstream fcitx5-qt race can also reorder fast
typing after focus is acquired. See the [README known issue](../../README.md#fcitx5-qt-can-reorder-fast-typing)
for shell launch workarounds and the verified compositor scope.

## Committed paste handoff

Providers submit paste intents through the launcher's `pasteText` or
`pasteClipboard` interface; they do not manage native focus or the paste queue.
`LauncherActionService` owns the destination/session and committed payload.
Logical close and object destruction are not native keyboard-release signals:
the overlay keeps its native window mapped, with keyboard focus disabled,
until the compositor acknowledges loss of activation. Both paste kinds wait
for that acknowledgement, no active shell window, and the captured destination
to be focused. The clipboard process is serialized by the same durable owner.
This handoff has no fixed delay and does not depend on provider/UI lifetime.
If the destination is absent or has closed, the intent still copies its
payload to the clipboard, without injecting a key into another surface.
