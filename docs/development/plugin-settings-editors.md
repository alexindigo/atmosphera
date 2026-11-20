# Plugin editor owner preparation

## Historical pre-cutover contract

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

Shared-base fences compare values; list commands additionally capture old-owner
notification generations. Notification-suppressed equal/nested ABA remains
undetectable: these are not configqml intent revisions. I5 replaces the factories with real configqml
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

The popup delegates its selected editor lifecycle to `PluginSettingsSession`.
That service owns opening, page API creation, staging/Apply, actual receipt
acceptance, dirty Close admission and deferred editor release. The popup keeps
layout, focus, confirmation presentation and loading/unloading the page. Native
controls enter through callbacks supplied by the presentation, not service
queries into a widget's internals.

`plugin-settings-session-regression.py` runs the actual popup and native owners
in the explicitly profiled VM: dirty Close/Keep/Discard, held and no-op receipts,
real permission failure/Retry, stale success retention, selected instance
Apply/Reset, independent files and separate cold consumers. This extraction
does not itself change page writer capabilities, desktop scope or the catalog;
those remain the coupled field-intent integration.

`PluginSettingsSession` creates a selected editor and the popup passes its
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
old-owner preparation, not an intent-revision, partial-shard or I6 timing claim.

## Captured placement commands

The old-owner instance editor captures its `Settings.createRecordListEditor`
session before opening. All four placement addresses (global bar, screen bar,
control-center and desktop) submit `set`/`unset` for `instanceSettings` only.
They do not replace an entire normalized display row. Runtime instance views
capture at their immediate save/reset command boundary; delayed editors retain
the original generation/address, including across failed-save retry.

Command admission and its current refresh must complete before requesting a
save receipt. An intervening list publication, including notified ABA with the
same final value, fails rather than recapturing the current row. Whole-leaf and
shared-base value fences remain additive under the old owner. Notification-
suppressed equal/nested ABA is still its documented limitation; I5 replaces this
factory with the actual normalized worker command/overlay contract.

## Native cutover witness

Native editors open asynchronously and own their editable values. Do not pass a
detached copy of `initialValue` to Apply:

```qml
var editor = pluginApi.createSettingsEditor();
editor.whenReady(function (result) {
  if (result.status !== "opened") {
    editor.discard();
    return;
  }
  editor.values.label = "New label"; // A field declared by this plugin's schema.
  editor.apply(editor.values, function (receipt) {
    // Inspect receipt.status and receipt.refreshState before saved feedback.
  });
});
```

`discard()` still refuses while busy. A presentation that is already closing or
being destroyed calls `release()` instead: the editor owns its deferred detach
through native Apply/Reset settlement and suppresses the released presentation's
completion callback. This does not authorize discarding user edits on an ordinary
Close; the popup's confirmation flow remains responsible for that decision.

The current owner uses `Scripts/dev/fixtures/settings-plugin-editors-native.qml`.
It retains shared Cancel/Apply, all four placement addresses, ABA/reorder/base/
unload refusals, real IO failure and Retry, sparse unknown fields, Reset, runtime
consumers and separate cold verification. The old-owner fixture belongs to the
pre-cutover commits and is not shipped in the current tree. The gate selects the
native witness at cutover; historical trees retain their own old-owner fixture.

## Runtime placement save and retirement Retry

Placement `saveSettings` requests selected publication of its owning atomic
settings key (for example `bar.widgets.left`), not a whole-store save. Failed
receipts retain their attempted, unconfirmed coverage keys. An explicit Retry
publishes the **current values of those same keys** through ConfigQml 0.5.1
`saveSelected`. A newer edit to a covered key is the user's latest intent for
that key. Keys outside the failed coverage are not saved, including unrelated
pending keys in the same JSON file or shared plugin settings. Successful later
requested coverage supersedes earlier failures on those keys; retirement never
retries newly unrequested edits after that success.

This is a current-intent Retry, not an exact original-value capture. ConfigQml
0.5.1 returns retained-group tokens asynchronously, so overlapping requests cannot
name an earlier token before its callback. A future native queued-capture facility
could support exact original-boundary Retry. It is not required for this contract.
List/record keys remain atomic: Retry does not invent a per-row persistence unit.
Same-owner retries retain the existing ready native owner until requested work
settles, then wait for placement API destruction before releasing that owner.
