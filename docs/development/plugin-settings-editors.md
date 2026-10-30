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

Popup page-API staging, dirty-close discovery for locally buffered pages and
receipt-driven popup feedback are still a separate required I4 boundary. The
runtime popup has not switched to these factories in this preparation commit.
