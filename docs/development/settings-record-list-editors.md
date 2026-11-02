# Captured record-list command preparation

## Approved C2 container commands (old-owner preparation)

The additional `Match` / `ensure` / `copy` / `at` shapes follow integration answer9
and its approved contract. They are implemented by the injected **old owner** in
I4; installed configqml0.3.0 is not asked to execute them. I5 maps them unchanged
to the separately implemented/published configqml0.4.0. No library code or version
floor changes are part of this preparation.

`createRecordListEditor(path, address, additionalLists, {ensure:true})` captures an
absent primary list as `initialValue: []` without creating a preference. Additional
selections may likewise carry `ensure:true`. Omit the fourth argument for existing
0.3.0 behavior. `session.target(targetIndex, ensureOverride)` returns the native
target/copy-endpoint shape (no index); `session.endpoint(index,targetIndex,
ensureOverride)` adds an index. An omitted override carries the captured ensure;
explicit `false` strips it for sources, where an ensure member is forbidden.
Indices are checked sequentially on submit, including after earlier copy ops.

Addresses accept first-match `{field:"name",equals:<opaque string>}` only at the
declared monitor-array Each ancestor. Later duplicate names are retained. The
factory validates the known policy shapes/required String match field; index
addresses never create. Resolution refuses present null/wrong-type containers.
Missing keys are created only with ensure (except the absent final list created
by copy), using the approved structural container-kind inference for these paths.
Reading/opening/canceling never submits; ensured empty batches refuse.

`copy` has exact `{op,from,to}` members, no index or row body. Its source must exist
and cannot carry ensure. The destination must be absent, even an existing `[]`
refuses. Only the destination is touched; both owners are fenced. The old owner
has identity projection, so the display-equivalence guard is trivially true and
its copied rows are effective legacy rows. C2 supplies native raw/numeric-atom
preservation, actual projection comparison and native route/mask/schema checks.
No GUI raw mirror or normalization engine is added here.

Local operations optionally carry `at:{policyId,listAddress,generation,ensure?}`.
All targets/endpoints are checked against initial captured generations before the
batch, then resolved per operation. All edits/creation happen in private candidates
before any setter; each touched owning leaf is assigned once. Existing old-owner
multi-leaf notification/ABA limits below still apply.

`setScreenOverride` and `clearScreenOverride` use the identity ancestor's captured
row commands. First property set inserts one record; existing property set/unset
changes only that member. Prune-on-empty counts the fenced record's own unknown
keys; only a remaining name/empty record is removed. Widget editing callers use
the child commands, not a replacement normalized `widgets` payload.

`settings-list-containers.qml` adds real old-owner absent-record/section capture,
three-source copy, first-match/unknown-key prune, null/type/index/source-ensure
refusals, stale absence/source fences, late-failure noncreation, same-leaf and
cross-leaf `at`, ensured transfer+placement, source-fence-only assignment counts,
actual persistence and separate cold restart. Existing transfer/selected-editor
and strict consumer lanes remain required. These fixture commands are also the
I5 facade obligation; native C2 implementation/tests are owned separately.

`Settings.createRecordListEditor(ownerPath, listAddress)` prepares the injected
command boundary for live placement editors. It returns `null` for unsupported
owners or missing lists. `ownerPath` is a segment-array atomic leaf; `listAddress`
uses concrete `{key: string}` / `{index: integer}` segments inside it. It never
invents per-row Settings namespaces or unique placement IDs.

The returned session exposes an owned `initialValue`, a captured `generation`,
`submit(edits, callback)` and `detach()`. Edits use configqml's record-list command
shapes: `set`, `unset`, `remove`, `insert`, `move`, `transfer`. Only explicitly submitted fields
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
callers. Configqml 0.3.0 supports a raw-preserving transfer in that same library
command, including distinct leaves in one store. Save remains separate; this is
not a filesystem transaction.

## Captured transfers

`Settings.createRecordListEditor(path, address, additionalLists)` accepts optional
`[{path, listAddress}, ...]` selections. Capture all possible destinations when
the menu/drag opens, not at drop/activation. `session.endpoint(index, targetIndex)`
returns an owned `{policyId, listAddress, generation, index}` endpoint; targetIndex
defaults to the primary selection (0). Treat policyId as opaque. The old factory
identifies the selected policy shape (array indices generalized to Each) separately
from its atomic owner, so screen sections have different policy IDs but share one
leaf generation/value fence. I5 supplies the declared worker policy identities.

Submit `{op:"transfer", from:session.endpoint(sourceIndex),
to:session.endpoint(destinationIndex, targetIndex)}`. No moved row body enters the
command. Every supplied endpoint must belong to the captured selection set and
match its original generation. All operations are checked against private selected
leaves before any setter; indices then apply sequentially, including same-list
destination slots **after removal**. Unknown/cyclic/malformed bodies, stale sources
or destinations and late invalid operations refuse without half-applying a batch.
The same atomic owner is copied/fenced/assigned once, even across monitor sections
or desktop monitor addresses. Subsequent callbacks retain both endpoint fences.

The old owner has no worker raw mapping or multi-leaf transaction: transfers move
its owned effective row, and distinct leaves still use its ordinary synchronous
setters. This adapter does not claim worker notification coherence, masked-route
admission or hidden-raw-row preservation on that backend. I5 replaces these
internals with the single published worker transaction (both leaves or neither),
retaining the exact injected transfer shape. Existing old-owner equal/nested ABA
limits above still apply. No shell raw mirror, diff or rollback owner is added.

`settings-list-transfers.qml` checks all four placement families, shared-leaf
assignment counts, repeated IDs, captured address/command ownership, both endpoint
fences, invalid batches, busy/detach, failed save/retry and independent cold restart.
`settings-native-transfer.qml` separately exercises installed configqml 0.3.0:
actual model consumers, coherent leaf generations, hidden sibling/raw-row retention,
no injected-default materialization, acknowledged save and cold restart.

The inert `Scripts/dev/fixtures/settings-record-list-editors.qml` exercises the real
old Settings factory, all seven owning leaves, sequential operations, opaque keys,
captured-address/command ownership, invalid-batch atomicity, stale repeated-ID rows,
notification ABA, async/busy/detach and actual save/cold-restart endpoints. Production
placement callers are ported separately; this foundation alone does not complete
normalized-list callback preparation.

Tray pin/unpin captures its command session, screen/global routing, placement
and tray identity at menu presentation, before menu-loading delays. It sets only
the `pinned` field through that retained session. Repeated-ID replacement,
notified ABA and routing changes refuse the command without editing either owner.
Immediate non-menu callers may capture at submission; successive commands wait
for the prior receipt. A failed aggregate save retains admitted input and the
session for explicit retry; drawer resizing follows current admission and is
independent of persistence feedback. `tray-pin-commands.qml` covers both owning
routes, these refusals, same-session retry and save/separate cold restart.
Disabled screen overrides follow the displayed global route. When monitor editing
first copies that global namespace, only the three declared list leaves enter
the new record; Qt signals are never enumerated into preference data. Existing
plain screen records retain their unknown members.

The VM driver must set `I4_SETTINGS_OWNER=legacy` or `configqml` explicitly.
Per coordinator `I4-answer-3`, only the old-owner cold-restart `__proto__` check
is an expected failure: the original assertion runs for each of the seven lists,
reports XFAIL with its reason, and an unexpected pass fails loudly. All live
adapter checks and the `constructor`/`prototype` checks stay hard assertions.
I5 must run the configqml mode with all three members surviving edit, save and
cold restart; there is no expected-failure allowance on that owner.

The runtime BarService settings launcher captures its field-command editor before
component loading, including the displayed global/screen route and original row
data. Component callbacks retain that editor, rather than using their later
section/index to select a newer placement. The service submits field commands,
then requests save only after current admission; a failed aggregate save retains
admitted input for same-session retry. Disabled overrides follow the displayed
global owner. Closing detaches the session without undoing live input.
`bar-settings-commands.qml` covers both routes, repeatable IDs, notified ABA,
route changes, competing commands, owned submitted fields, failed-save retry and
separate cold restart. Core pages' legacy whole-row signal payloads still need
their explicit user-field port; excluding their unchanged id at this boundary is
compatibility preparation, not proof that default-valued fields are intentional.

The live bar dialog receives that session directly, keeps the captured row as
its initial input, and uses `NLiveSettingsEditSession` for debouncing and owned
queued fields. Close waits for a nonfailed current persistence receipt. Failed
or stale input remains in the open dialog for explicit Retry or confirmed local
discard; canceling that confirmation retains it. Discard never rolls back live
settings already admitted. New input during an outstanding save is queued, not
silently swallowed. The real-dialog fixture also covers failed Close, retry,
stale refusal and both branches of discard confirmation. Existing immediate
controls remain immediate/debounced, without a new Apply/Cancel workflow.
