# Native field capabilities

`createSettingsEditor(true)` opts into settled field metadata captured with the
native selected editor. Calls without the flag keep their existing contract.
Plugin-level captures record each declared field's native publication generation
and whether its winning source is the writable route. Placement captures retain
their existing base and owning-leaf generations. Metadata never becomes a
persistence snapshot.

`PluginSettingsFields` owns stable configuration/content handles around that
editor. Compound reads are isolated presentations; only explicit `set` and
`reset` carry intent. A finite multi-field `resetFields(keys)` is one native
`stageReset` in plugin scope or an `unset([key])` for each requested atomic
path in instance scope, followed by one Apply. Native staged Reset
reveals the lower level; no manifest-default assignment substitutes for it.
Accepted-current receipts recapture stored facts before observers.

Each runtime API also owns a stable read-only `settingsContext`. Its identity
is the captured API, not an equal configuration value or a renderer. Consumers
read copied effective values and check `current()` before publishing results.
Retired APIs cannot become a replacement placement by recapturing an index.

`plugin-settings-shared-native-regression.py` exercises the shared adapter and
runtime context without a generic page: native Set, staged Reset, Discard,
Apply, bound text consumers, unrelated/opaque file preservation and a separate
cold engine. The host/assets driver's `fields` case covers all four placement
families independently. These preparation gates do not certify page adoption.
