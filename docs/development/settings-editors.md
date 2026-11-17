# Settings editor preparation

## Scoped publication on the native owner

Per-edit persistence uses `Settings.saveSelected(paths, callback)`, where paths
is a nonempty array of segment-array leaves/namespaces. It forwards directly to
native `saveSelected`; it never falls back to a root save. Callers name exactly
the leaves they wrote. Resets publish their removed leaf/namespace through the
same selected API. Native list/record commands keep their captured owning atomic
leaf, including both owning leaves for a transfer, rather than addressing row
members as settings paths.

`Settings.saveResult(callback)` remains the full-prefix root save for profile
save-everything and explicit whole-store test fences. Its unresolved-work refusal
and blocker reporting are unchanged. Selected receipts still reach the shared
completion/success/failure signals, and optional callbacks remain optional.
The callback-only `Settings.saveImmediate(callback)` is retained unchanged for
older plugin consumers; new shell per-edit callers use the explicitly named
selected operation rather than overloading that compatibility entry point.

This integration requires the unreleased configqml 0.5.1 additive API for the
Atmosphera 0.10.0 release. The declared package floor intentionally stays 0.5.0
until the separate library release/version-preparation step.

## Earlier preparation contract

Completion callbacks are optional: a missing/non-function observer is not
invoked. Admission, persistence, owner notifications and internal editor state
settlement still occur. A caller requiring a result supplies a function and
observes its status; callback absence never means an operation is saved.

The production Settings owner remains the legacy owner until the single configqml
cutover. Hook and idle command editors now consume an injected editor with
`initialValue`, `apply(value, callback)` and `discard()`. The popup owns its local
input, submission, busy state and explicit dirty-discard confirmation. A failed
receipt (or a non-current overlay refresh) retains the input. Test commands still
receive local text and are separate shell effects.

`Settings.createEditor(path)` is a transitional **selected scalar value** adapter.
It compares the selected value before assignment and rejects intervening changes;
it is not a revision fence and cannot detect equal-value/ABA changes. I5 replaces
the factory with real selected-path drafts after pending input settles. It is not
a second persistence engine and never snapshots the full graph. Failed Apply has
already admitted live input in the old owner; discarding the popup does not undo
that admitted intent or report it as saved.

Idle's owning leaf remains the JSON string `idle.customCommands`. Its owner captures
that string and validates the index before opening. Apply builds the replacement
from the captured string, retaining unknown record fields. A changed list rejects
the edit rather than applying the old index or turning a missing row into an add.
Malformed input is retained and refused, not replaced with an empty list.

`Settings.saveResult(callback)` is additive: it delivers an asynchronous result
with explicit `saved`, `nothing_to_save` or `failed` status and a value-free error
code. The old Boolean callbacks and legacy save signals remain compatible. The
old owner supplies only these fields: this is not a fabricated configqml receipt
with request IDs, coverage or revisions. I5 forwards the complete library result.

The inert `Scripts/dev/fixtures/settings-editors.qml` exercises actual hook/idle
popups, the real idle owner and old Settings persistence. It verifies dirty Cancel,
keep-editing, busy competition, failed/current/stale receipts, stale index refusal,
unknown-field retention, saved/no-op callback ordering and cold restart consumers.
It is copied to the installed candidate root by the VM-only gate driver and runs
on real Wayland. It never executes hook commands. This fixture does not stand in
for the remaining plugin popup, live placement/normalized-list and domain editors.
