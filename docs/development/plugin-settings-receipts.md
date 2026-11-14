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
This prerequisite does not complete plugin popup/instance editing or catalog work.
