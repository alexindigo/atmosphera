# Plugin save acknowledgement preparation

Until I5 replaces the plugin settings owner with configqml, `saveSettings(callback)`
is additive: existing callers can omit the callback. The callback receives explicit
`saved`, `nothing_to_save` or `failed` status and a value-free error. This is not a
full configqml receipt with request identities, revisions or coverage.

The service captures each submitted body before queueing it. A service-owned FIFO
preserves request and completion order across failures and reentry. The completion
signal precedes the detached callback; callback failures cannot stop the queue.
Existing immediate API reassignments still invalidate live consumers before disk
settlement, preserving the old owner's behaviour.

The stdin-only child reuses `section-io.py` for inspect/prepare/promote/readback.
It publishes a complete old-owner snapshot, not a sparse descriptor-aware file.
A configured file symlink is retained and its resolved target is published; target
retargeting detected between stages fails. This is not universal filesystem CAS,
power-loss durability, cross-file atomicity or an editor revision fence. Conflicts
and failed prepared work remain private task data, never callback payloads. The
plugin-dir legacy file remains a read-only fallback. Plugin state is separately
owned. I5 removes this transitional transport with the old plugin persistence path.

`Scripts/dev/fixtures/plugin-settings-receipts.qml` observes actual API bindings,
asynchronous receipts, signal-before-callback, failure/FIFO/reentry, submitted-alias
isolation, linked publication and a cold restarted API consumer. The VM-only driver
also inspects final target bytes, link identity and failed destination contents.

## Native cutover witness

The current owner uses `Scripts/dev/fixtures/settings-plugin-receipts-native.qml`.
It retains asynchronous ordered receipts, signal-before-callback delivery,
rejected input, owned submitted values, real IO failure, linked-file publication
and a separate cold consumer. This witness checks work queued before completion
and explicit sequencing across independent native owners, not same-owner callback
reentry while another request remains queued. Independent owners are sequenced
at the caller boundary rather than through the removed shared serializer. The
old-owner fixture remains in historical pre-cutover trees, not the current tree.
This prerequisite does not complete plugin popup/instance editing or catalog work.

## Load and retirement ownership

Service.loadPlugin retains one generation while settings, state, translations and
data-only registrations complete. Its optional third callback receives `loaded`
or `failed`; the existing second callback remains bar-registration specific.
Duplicate requests join that generation and receive independent completions.
Only initialization loads decrement startup accounting, once per generation.
Unload cancels the generation before native owner retirement, so a late reader
cannot register components or data with a retired owner. Plugin-created reentrant
unload also invalidates the remaining registrations. A replacement workflow must
await this full-load receipt, not treat starting loadPlugin as successful loading.

Update and hot reload keep one replacement operation through retirement, optional
installation, and full replacement loading. Failure retains the operation for a
same-owner Retry. Update does not install files after a failed final save and does
not clear its notice until replacement loading succeeds. Failed update/reload
operations expose the existing error toast's Retry action, bound to that retained
operation; stale actions cannot start another replacement. Hot reload emits its
success signal/toast only after the replacement native owner and registrations
are ready. Uninstall also waits for retirement before removing files.

Updates preserve placement settings in place during retirement, rather than
disabling/removing the placements and restoring a stale layout snapshot over
concurrent user edits. A disabled plugin stays disabled after updating. Shared
and placement requested saves use bounded native saveSelected publication;
current-intent Retry and later-success supersession are described in
[plugin-settings-editors.md](plugin-settings-editors.md#runtime-placement-save-and-retirement-retry).
Any successful native writer on those covered keys supersedes earlier failed
coverage, including dialogs and autosave, not only another plugin API save.
