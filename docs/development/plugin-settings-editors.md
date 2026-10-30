# Plugin editor owner preparation

Plugin APIs expose `createSettingsEditor()`. The returned selected-value handle
has `initialValue`, `apply(value, callback)`, `resetOverrides(callback)` (instance
only), and `discard()`. It is separate from the live runtime API. Unapplied values
are owned copies and Cancel changes neither owner nor files. Apply owns its input
before assignment, awaits the actual persistence callback and reports additive
`refreshState: current | stale | not_refreshed` facts. Busy/discard/closed requests
are refused. Failed old-owner input may already be live; discard never rolls it
back. Retrying that own admitted value remains possible.

The shared factory captures the selected plugin settings and loaded API identity.
The instance factory captures that base plus the complete owning leaf: one global
bar/shortcut list, all screenOverrides, or all desktop monitorWidgets. Reordering
same-type placements, editing another row in that leaf, deleting the placement,
changing the shared base or unloading/replacing the API refuses the stale editor.
Sparse merge/difference stays with the existing PluginInstances owner. Reset
explicitly removes all overrides, without writing the shared plugin file. Both
legacy instance save/reset methods also accept additive structured callbacks.

These are **value fences**, not revision fences: the legacy owner does not expose
equal-intent/ABA generations. I5 replaces these factories with real configqml
selected drafts and two-owner overlay editors, worker merge/difference and
normalized-list generation mapping. Do not carry the transitional JS value-stamp
adapter into the new production owner. There is no per-row ConfigScope or claimed
cross-file transaction here.

The inert `plugin-settings-editors.qml` fixture exercises shared Cancel and Apply,
submitted-alias ownership, repeated-ID move/base/unload conflicts, a real failed
save and retry, all four placement addresses, sparse unknown-override preservation,
instance reset, persisted files and cold restarted effective consumers. The
failure witness uses the old owner's unresolved-managed-work aggregate failure;
ordinary routes can already be confirmed even when that full receipt fails, so a
subsequent retry may truthfully be `nothing_to_save`. It is not an injected
instance-file IO/partial-publication witness.

## Popup and page staging

`NPluginSettingsPopup` creates a selected editor and passes an editor-only
`PluginSettingsPageApi` through PluginLoader's existing initial-properties
boundary. Its `pluginSettings` belongs to that page, not the live runtime API.
The page's synchronous `saveSettings()` gathers local controls into this value.
`pluginApi.saveSettings(callback)` stages input only; multiple calls do not apply
or write disk. The popup owns exactly one Apply after page staging returns.
Callbacks receive the actual owner result, after the popup's `settingsCompleted`
signal. Pages must use the callback/signal for saved feedback rather than claiming
success when staging returns. Explicit state/config/application actions retain
their existing owners and are not part of the preference transaction.

Pages may expose reactive `readonly property bool settingsDirty` covering all
locally buffered input. This must not call Save or otherwise publish changes.
Without that contract the popup conservatively confirms Close even when its API
has no staged input: local control state cannot safely be inferred from draft
dirtiness. Failed/stale Apply always retains the page and requires explicit
discard. Busy blocks Apply, Reset, Close, page input and auxiliary buttons.
Close buttons and Escape share the confirmation flow; outside auto-close is
disabled. A second Open refuses to replace an existing editor.

Only `saved`/`nothing_to_save` **and** `refreshState: current` allow saved feedback.
Reset has its own explicit confirmation and uses the captured editor's
`resetOverrides(callback)`. It reloads the page only after that same accepted
receipt; failures retain the page/confirmation. Page initialization and confirmed
Cancel never invoke the live owner's preference writer. Destruction still follows
the existing owner lifetime: already admitted failed input is not rolled back.

The inert `plugin-settings-popup.qml` witness hosts the actual popup and page in
a real Wayland window. It covers buffered dirty-close/keep/discard, no load/Cancel
write, staging twice with one Apply, held actual receipts, busy competition,
failed destination retention, truthful saved-but-stale handling, shared/instance
consumers, acknowledged instance reset, unknown owner fields, legacy-page Close
confirmation, independent disk readback and separate cold restart. This remains
old-owner preparation, not a revision/ABA, partial-shard or I6 timing claim.
