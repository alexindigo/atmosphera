# Generic page field capabilities

Every generic `settings` entry receives the selected session's field-only
page API. The complete official catalog, shipped demo and generic fixtures use
this contract. Runtime and `desktopWidgetSettings` APIs remain separate.

`PluginSettingsSession` owns the selected native editor, field facts, staging,
Apply and receipt acceptance. It replaces the P001 safety API's mutable page
namespace and session-level reviewed Reset path. The popup only presents the
page and confirmation; it does not reconstruct preferences from controls.

The page's `pluginSettings` and `initialSettings` are isolated read projections,
not publication namespaces. `field(key)` returns a stable configuration handle
with `value`, `present`, `inheritedValue`, `inheritedPresent`, `overridden`,
`pendingIntent`, `error`, `receipt`, `set(value)` and `reset()`. Only explicit
user events or committed input call `set`. Loading or comparing displayed values
never creates intent. False, zero, empty and absent values remain distinct.

Wrap each atomic preference control in `NPluginSettingsField { field: handle }`.
The chrome shows stored versus pending state and stages per-field Reset. A
host-owned summary covers declared configuration overrides not presented by
the page, without exposing their values or secrets. Compound fields stay atomic;
copy a display value before constructing an explicit replacement in a user event.

`saveSettings(callback)` only registers completion/staging compatibility. It
does not accept a snapshot or publish. A page's optional synchronous
`saveSettings()` commits its still-buffered field intents; `settingsDirty`
describes that input without saving. Only the session calls native Apply with
the selected editor's own values identity. Only `saved` or `nothing_to_save`
with `refreshState: current` acknowledge completion. Signals precede callbacks;
failure/stale results retain input for Retry or confirmed discard.

`contentField(key)` is available only for declared legacy content in plugin
scope and only for the content feature's explicit commands. Instance scope
cannot obtain it. Operational leaves have no Settings setter. Configuration
Apply/Reset never collects Todo tasks/pages/counters or other shared content.
No content is migrated. External generic pages must adopt this API; runtime
APIs are refused at `PluginLoader` before generic page construction.

For a declared String configuration leaf `message`, the same page works in
either selected scope:

```qml
import QtQuick
import QtQuick.Layouts
import qs.Widgets

ColumnLayout {
  id: root
  property var pluginApi: null
  readonly property var messageField: pluginApi?.field("message") ?? null
  readonly property bool settingsDirty: false

  NPluginSettingsField {
    field: root.messageField
    NTextInput {
      id: messageInput
      label: "Message"
      text: root.messageField?.value ?? ""
      onEditCommitted: root.messageField.set(messageInput.text)
    }
  }

  function saveSettings() {
    pluginApi.saveSettings(); // Observe the session's eventual completion.
  }
}
```

The normal host input guard commits active native text buffers before Apply or
Close. Custom buffers additionally expose `settingsDirty` and commit only their
own finite field intents from the page's `saveSettings()`.

## Native adapter and runtime context

`createSettingsEditor(true)` opts into settled field metadata captured with the
native selected editor. Calls without the flag keep their existing contract.
Plugin-level captures record each declared field's native publication generation
and whether its winning source is the writable route. Placement captures retain
their existing base and owning-leaf generations. Metadata never becomes a
persistence snapshot.

`PluginSettingsFields` owns stable configuration/content handles around that
editor. Compound reads are isolated presentations; only explicit `set` and
`reset` carry intent. A finite multi-field `resetFields(keys)` is one native
`stageReset` in plugin scope or an `unset([key])` for each requested atomic
path in instance scope, followed by one Apply. Native staged Reset
reveals the lower level; no manifest-default assignment substitutes for it.
Accepted-current receipts recapture stored facts before observers.

Each runtime API also owns a stable read-only `settingsContext`. Its identity
is the captured API, not an equal configuration value or a renderer. Consumers
read copied effective values and check `current()` before publishing results.
Retired APIs cannot become a replacement placement by recapturing an index.

`plugin-settings-shared-native-regression.py` exercises the shared adapter and
runtime context without a generic page: native Set, staged Reset, Discard,
Apply, bound text consumers, unrelated/opaque file preservation and a separate
cold engine. The host/assets driver's `fields` case covers all four placement
families independently. These native gates prove their stated adapter boundaries,
not catalog runtime effects. The catalog page regression separately exercises
each manifest entry and Settings child in both scopes through its actual page
signal, native Apply/Reset and independent files; it does not construct Main.
The focused selected-client and Pomodoro input gates provide their additional
real-input/runtime-consumer proof. ConfigQml >=0.5.2 is required.

`plugin-settings-lock-focus-regression.py` is a separate, explicitly authorized
real-lock proof, not the in-shell preview test. It uses an explicit guest profile
and the installed bundled locker on the guest's niri session. Candidate and
previous NToggle variants must keep the actual password input focused through
Tab/Backtab, isolate an independent background input/toggle, reject a wrong PAM
password, then show successful PAM before the single protocol unlock. No test
method grants authentication, changes focus or unlocks. Successful cleanup
restores the guest credential and joins the actual holder; failure preserves
private recovery material inside the guest and never kills a secure holder.
Inherited locker diagnostics are compared and reported separately from focus
outcomes. This focused test does not certify a clean locker runtime or replace
the locker lifecycle/Locker1 contract matrices.
