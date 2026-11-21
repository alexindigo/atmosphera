# Plugin settings editors

## One selected native owner

The generic `settings` page is an editor, not a live runtime plugin. Settings ->
Plugins selects plugin scope. Global/monitor Bar, Control Center, Desktop
Widgets list gear and runtime desktop generic Settings select their captured
placement. Explicit plugin-level IPC/BarService entry points remain plugin-level.
Core and `desktopWidgetSettings` pages keep their separate live-field contract.

`PluginSettingsSession` owns the existing ConfigQml draft/overlay, field capture,
page capability, Apply/Reset, receipts and release. `NPluginSettingsPopup` renders
that session and supplies input commit/capture/acknowledgment callbacks. There
is no second settings engine or page snapshot writer. `PluginLoader` requires
the editor role before constructing a generic page through either creation path.

The runtime desktop fallback captures the placement before asynchronous loading
and opens the same session as the list gear. Generic Close never invokes the
removed live-dialog Save-on-Close path. The field-only API supersedes the earlier
P001 safety unit's mutable namespace and reviewed session Reset dispatch.

## Page intent

See [field capabilities](plugin-settings-field-capabilities.md) for the complete
page surface. `pluginSettings`/`initialSettings` are isolated read projections;
only `field(key).set(value)` and `field(key).reset()` submit configuration intent.
The control's user event or committed input owns that call, not initialization,
translation, range projection or an effective-value comparison. Atomic lists,
records and maps remain one declared preference leaf.

`NPluginSettingsField` takes the injected handle and presents inherited/stored
override state, pending intent and Reset. Undisplayed configuration overrides
appear in the host summary without their values. Native equal-to-base omission
removes an explicitly edited equal override. Untouched known/opaque overrides
are retained. Plugin-level changes propagate only through inherited fields.

Pages may keep local input buffers. Their synchronous `saveSettings()` commits
only those buffered field intents. `settingsDirty` is a read-only local-input
predicate, never a Save. `pluginApi.saveSettings(callback)` only registers a
completion observer; it neither ingests a snapshot nor publishes. The session
calls one native Apply with the selected editor's own `values` identity.

Legacy shared content remains in place. `contentField(key)` exists only in
plugin scope for explicit content commands. Instance configuration cannot obtain
it; operational leaves have no generic Settings setter. Todo instance pages
explain why shared page/task management is unavailable. Configuration Apply and
Reset never collect tasks/pages/current-page/counters or opaque content.

## Reset, results and lifetime

Field Reset is staged: native `unset([key])` for an instance, native
`stageReset([[key]], callback)` for a plugin draft. A finite multi-field control
uses `resetFields(keys)`. Native lower-level presentation replaces the removed
choice; a manifest-default assignment is not Reset. Discard does not publish it.
Whole instance Reset removes declared configuration overrides only, followed by
one Apply. It never calls the native all-data `resetOverrides` on mixed content.

Only `saved` or `nothing_to_save` with `refreshState: current` acknowledge work.
Accepted-current field recapture precedes observers. `settingsCompleted` precedes
callbacks. Failed/stale results retain input/preview for Retry or confirmed
discard; busy excludes competing input/actions. A second Open refuses replacement.
Ordinary Close uses dirty confirmation. Genuine presentation loss uses native
deferred `release()` and fences late callbacks, not a forced busy discard.

Both presentation settlement and actual session destruction use the same
selection-resource release. The session closes its provided-editor preview
before disappearing, and the native editor still retires only after becoming
idle. Otherwise the runtime owner could retain a dead preview admission and
refuse the next editor even after native persistence had settled.

Settings hosts inject `registerPresentation` into the generic popup. From native
editor selection through release, its host registers only a request-Close
callback with SettingsPanelService. Tab/sidebar/search/subtab, native window
Close, service Close and panel replacement consult that admission before hiding
or replacing content. A refusal keeps the same page/input and confirmation;
neither a retained editor alone nor a post-destruction discard is sufficient.
After explicit Apply or Discard, retry the requested navigation. No old request
automatically navigates a later session. Ordinary panels without an injected
Close admission retain their existing behavior.

An unexpected native hide or direct `Popup.close()` also cannot unload a dirty
or busy selected page. The popup asks the same session, keeps that exact loaded
page on refusal and restores its presentation. PanelService propagates the
runtime popup host's Close refusal before claiming a replacement panel, rather
than covering a retained dialog with another keyboard owner.

Discard of unapplied input is nonpublishing. It does not undo an already
requested Apply: ConfigQml retains admitted requested persistence through
detach, including a failed publication. The main Settings owner's autosave may
later publish that admitted placement intent; the manual plugin owner does not
autosave it. Failed receipts still cannot acknowledge input or a refresh.
`plugin-settings-navigation-regression.py` separates those two cases and records
independent final files, instead of promising rollback of requested native work.

The native editor captures base and owning-leaf generations. A changed capture,
same-ID replacement, reorder, base change or owner loss cannot retarget it to a
new placement. A closed/conflicted editor cannot recapture an index to recover.

ConfigQml >=0.5.2 is required for untouched-overlay preservation and native
staged draft Reset as well as selected publication. Package, Nix and devcontainer
pins select the signed release; stock 0.5.1 lacks those first two contracts.

## Selected runtime consumers

Runtime APIs retain their live preference contract, distinct from page APIs.
Each API owns a stable read-only `settingsContext`. Configuration-dependent
Main-owned clients use that captured context, not the shared Main configuration
for every instance. One API shared across views keeps one client. Retired query
generations cannot publish into replacement accounts, repositories or locations.

## Runtime placement save and retirement Retry

Placement `saveSettings` requests selected publication of its owning atomic key,
not a whole-store save. Failed receipts retain unconfirmed coverage. Explicit
Retry publishes the current values of those same keys through native
`saveSelected`; later success on covered keys supersedes earlier failures.
Unrequested keys and shared plugin settings are not included. This is current-
intent Retry, not an exact original-value capture or per-row transaction.
Retirement retains the ready native owner until requested work settles, then
waits for placement API destruction before releasing that owner.

## Verification boundaries

The P001 safety regression command now runs field-only real desktop routes,
keyboard input, permission failure/Retry, protected configuration Reset,
independent files, explicit shared content commands and separate cold consumers.
The session suite separately covers held/current/no-op/stale receipts, busy and
dirty-close behavior. Four-family native fields and shared-field gates cover
sparse metadata and staged Reset. Catalog page tests cover both scopes and
their loaded children, but do not construct every Main or claim unrelated
runtime defects fixed. Focused selected-client and P169 three-input tests carry
their own consumer claims. The final integration matrices remain separate gates.

The named-guest `plugin-settings-lifetime-regression.py` adds selected-session
base-change/equal/ABA, source-content/inode replacement, actual plugin unload,
held receipt, busy/delayed destruction and released-selection callback cases.
It observes bound runtime text, readable retained fields, independent files and
a separate cold engine. The preview-chain case observes shared preview below
stored overrides below the selected preview across all four placement families.
Closing either preview reveals current underlying values, never an opening
snapshot. A replacement preview must acquire the released owner's admission.
These synthetic session-contract cases do not certify catalog Main/actions.

An equal-byte new-inode shared source is intentionally distinct from a frozen
overlay source: native drafts fence selected path content and intent; overlays
also retain source provenance. The suite checks the shared admitted-current
outcome and the overlay refusal separately, plus changed-content replacement
refusal for both. No shell inode fence changes the native contract.

Historical old-owner preparations and mutable page examples remain in Git
history; they are not current extension instructions.

`plugin-settings-entry-routes-regression.py` constructs actual BarTab,
MonitorWidgetsConfig and ControlCenterTab owners and invokes their section
editor's public gear handler. Five cases cover global, monitor-specific and
monitor-inherited Bar lists plus both shortcut sections. Production signals
must capture the expected instance before page creation. Discard, Apply,
field/whole configuration Reset, real IO failure/Retry and same-ID replacement
have exact independent owning-file checks. Separate cold readers observe the
edited, whole-Reset, retried and final replacement boundaries without publishing.
Disposable wrong-list/section controls must fail at the selected-context assertion.
This is entry-route proof with a reviewed synthetic field page, not additional
catalog Main/action or physical input coverage. The seed explicitly stores the
existing Bar margin values, so it does not certify unrelated appearance controls
as nonpublishing when their choices are absent.
