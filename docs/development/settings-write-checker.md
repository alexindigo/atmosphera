# Detached settings write gate

`check-settings-writes.py --check` parses QML and embedded JavaScript with the
pinned tree-sitter QML/JS grammar. A parse error fails closed; strings, comments
and regular expressions are syntax, never assignment-shaped regex matches.
`Configs/settings-schema.json` provides the generated namespace/atomic path kinds.

The shared `settings-contract-check.py` runs schema parity/freshness, detached
writes, search freshness and focused analyzer/schema fixtures. The normal hook
runs it inside the resource-capped Podman tooling environment **after formatter
restaging**, against an exported `git write-tree` snapshot. Tools and inputs both
come from that final index. Unstaged/untracked data cannot make a stale staged
schema pass or contaminate the generated search index. CI checks the full checkout
with the same entrypoint/image. No application build or live shell runs in hooks.
All inputs are checked, so Tabs/SettingsContent/Widgets/translations and deleted or
renamed inputs need no fragile trigger whitelist. The search index remains UI
metadata, not schema-derived labels.

## Proof rules

| # | Flow | Classification |
|---|---|---|
| 1 | `Settings.data`, a declared `ConfigStore` id's `values`, declared scoped handle `values`, and namespace aliases | Attached QObject namespaces; direct property-origin setters/mutators are allowed. Ordinary JS-local aliases do not automatically detach. |
| 2 | QML `var`/list storage of a declared list/record/map, raw settings-fed `modelData`, explicit slice/filter/map/concat/spread/JSON copies and simple getter-return boundaries | Detached compound value with an origin and copy identity. Nested/index/length/delete/update/mutator writes create a publication obligation. |
| 3 | Explicit assignment of that copy/its lineage to its originating attached path, directly or through a proven single-setter wrapper | Clears the corresponding obligation. Nested copied children must be explicitly reinserted into the published owning aggregate; merely saving an unchanged parent does not cover them. |
| 4 | Statements and effectful expressions | One evaluator carries separate proof states through `if`, early return/finally, `&&`, `||`, `??`, `?:` and logical assignment, including conditions, arguments and initializers. An obligation must be published on every modeled normal exit. Literal short-circuit conditions retain their reachability; explicit abnormal throws are not normal exits. |
| 5 | Lexical/function/parameter shadowing, alias reassignment | Shadowing kills provenance; overwriting an alias never silently erases an already outstanding edit. Callback element aliases from known array operations retain the source copy identity. |
| 6 | Unknown calls, escaped returned copies, unmodeled loop/backedge/switch flow, unresolved computed owners | Advisory owner-review boundary. Nested effects are inspected, but their publication cannot erase the incoming or newly observed obligation. Arbitrary third-party callbacks/component contracts are not inferred from their names. Computed source/destination spellings are not equated just because both contain an unknown segment. |
| 7 | Undeclared literal namespace writes | Error. Guarded/compatibility reads of absent keys are advisory; atomic record payload keys remain owned unknown JSON, not bogus namespace typos. |

Function summaries belong to **declaration identities**, with QML object,
component, lexical and receiver lookup. Every declaration shadows outer methods,
including a child no-op or a method for which no summary can be proved. Parameters,
local functions/variables and receiver aliases participate in lookup. `root.save`,
`this.save`, literal bracket receivers and unqualified same-owner wrappers can
resolve; an unresolved/differently-owned call receives owner review rather than
borrowing a same-spelled setter from another object. Only pure getter returns and
one unconditional setter assignment qualify as summaries. Pure local aliases/copies
before a getter return are allowed; actual call arguments are substituted through
those helpers. Effectful getter expressions and complex wrappers remain unproven.

Computed primitive local keys retain their captured identity (and simple aliases)
between a read and its assignment-back. Assignment, update, augmented assignment,
lexical shadowing and lossy joins cannot borrow the previous identity. Unknown
expressions, calls used as keys and live QML key properties remain owner review.
Distinct keys never compare equal merely because both are dynamic. Schema-kind
lookup generalizes a captured key; publication still compares its exact identity.

The existing `Settings.getScreenOverrideEntry(screen)` value boundary and
`Settings.setScreenOverride(screen, literalField, value)` command are recognized
for the same captured screen/field, including simple wrappers selected by their
actual receiver. Mixed effective `getBarWidgetsForScreen` results remain unknown
owners; no screen/global branch is guessed. Opaque loops remain advisory.

Equivalent ownership states coalesce. Argument/object-field sequences join
primitive results only when their proof states, references and ownership members
are identical, avoiding an irrelevant scalar Cartesian product. More than64
distinct ownership alternatives emits an advisory and retains all pending work;
the conservative join cannot select one alternative's callable as a publishing
method. Opaque control flow never silently discharges an edit.

Scoped stores are recognized from actual declarations, not any object
with a property named `values`. Inline QML object/delegate storage is tracked;
arbitrary cross-file injected component contracts remain an advisory/review
boundary. This checker is neither a universal effect system nor a save-time diff
that recovers lost writes. It does not ban all `push` calls or claim every QML
`var` is a mutable live settings handle.

An intentional local draft may suppress one mutation using an immediately
preceding `// settings-write: intentional-copy -- <specific owner/reason>` comment.
An empty reason is ineffective. The CLI still reports the suppression as advisory;
there is no whole-file exclusion or automatic baseline allowlist. Fix missing
provenance structurally or document the exact ownership boundary; never loosen
the gate just because a new caller fails it.

## Guest checks

In the assigned VM, use a disk-backed venv with
`.devcontainer/settings-check-requirements.txt`, then bounded commands through
the task's guest connector:

```sh
python3 -B Scripts/dev/settings-writes-selftest.py
python3 -B Scripts/dev/settings-staged-selftest.py
python3 -B Scripts/dev/check-settings-writes.py --check --report "$EVIDENCE/writes.json"
python3 -B Scripts/dev/settings-contract-check.py
```

The fixture catalog includes hits and negatives for direct/attached writes,
namespace aliases, QML var/list copies, delegates, scopes, getter boundaries,
callbacks, nested edits, assignment-back, early exits/finally, effectful expression
branches, duplicate getter/setter names, actual receiver resolution, lexical
shadowing and bounded sequence growth, unknown flow, intentional-copy reasons and
parse rejection. Positive wrapper fixtures require no advisory, so replacing all
summaries with warnings cannot satisfy them. Staged tests prove
index/restaging ownership independently of working-tree content. Application
regressions still prove actual persistence/consumers; a static PASS is not that
runtime proof.
