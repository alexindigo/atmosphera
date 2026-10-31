# Captured record-list command preparation

`Settings.createRecordListEditor(ownerPath, listAddress)` prepares the injected
command boundary for live placement editors. It returns `null` for unsupported
owners or missing lists. `ownerPath` is a segment-array atomic leaf; `listAddress`
uses concrete `{key: string}` / `{index: integer}` segments inside it. It never
invents per-row Settings namespaces or unique placement IDs.

The returned session exposes an owned `initialValue`, a captured `generation`,
`submit(edits, callback)` and `detach()`. Edits use configqml's record-list command
shapes: `set`, `unset`, `remove`, `insert`, `move`. Only explicitly submitted fields
change existing rows. New records are explicit user input. A batch validates
completely before one owning-leaf assignment; indices apply sequentially. Capture
the session when a dialog, menu or drag starts, rather than at its later callback.

Submission returns old-owner synchronous admission only; its asynchronous callback
reports `admitted` or `failed`, never `saved`. `refreshState` distinguishes a current
admission from intervening input. Save-on-close/debounce owners separately await
`Settings.saveResult` wherever feedback promises persistence. A busy session refuses
competing commands; a detached session refuses new commands. Already admitted live
input is not undone by detach, and its completion still arrives.

This is a transitional **old-owner** adapter. Notification generations cover the
three global bar leaves, two shortcut leaves, screenOverrides and monitorWidgets.
Complete selected-leaf value comparisons additionally reject changed nested data
and repeated-ID reorder/replacement. Equal assignments or nested ABA that emit no
old-owner notification remain undetectable. These are not configqml intent revisions,
worker publication generations, normalized raw mappings or a persistence receipt.
Only the selected atomic leaf is copied, never the whole Settings graph.

Owned records use null prototypes, including existing unknown members, so opaque
`__proto__` fields remain data at the old QV4/QVariant boundary. The value fence
orders dictionary keys canonically; QObject admission can reorder them without
changing a setting. Unsupported/cyclic command input is refused before assignment.

I5 replaces the factory/old adapter and notification counters with captured
`info(path).publicationGeneration` plus `editRecordList(policyId, {generation,
listAddress, edits}, callback)`. The worker resolves display-to-raw rows and preserves
hidden/deprecated data without materializing injected defaults. Preserve field intent,
captured generation, busy/conflict handling and existing immediate/debounced UX at
callers. Cross-section moves between distinct owning leaves require their own owner
coordination; they are not a single library list command or filesystem transaction.

The inert `Scripts/dev/fixtures/settings-record-list-editors.qml` exercises the real
old Settings factory, all seven owning leaves, sequential operations, opaque keys,
captured-address/command ownership, invalid-batch atomicity, stale repeated-ID rows,
notification ABA, async/busy/detach and actual save/cold-restart endpoints. Production
placement callers are ported separately; this foundation alone does not complete
normalized-list callback preparation.

The VM driver must set `I4_SETTINGS_OWNER=legacy` or `configqml` explicitly.
Per coordinator `I4-answer-3`, only the old-owner cold-restart `__proto__` check
is an expected failure: the original assertion runs for each of the seven lists,
reports XFAIL with its reason, and an unexpected pass fails loudly. All live
adapter checks and the `constructor`/`prototype` checks stay hard assertions.
I5 must run the configqml mode with all three members surviving edit, save and
cold restart; there is no expected-failure allowance on that owner.
