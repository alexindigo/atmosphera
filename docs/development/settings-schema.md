# Settings schema inputs

The production Settings adapter remains the active owner until the integration
cutover. `Configs/defaults.json` is the authored reference-value tree for the
generated configqml schema. `Configs/settings-schema-overlay.json` supplies the
information JSON cannot express: real versus integer, atomic records, all 36
list element descriptors, optional fields, closed choices, and sensitive /
machine-local metadata. Paths are segment arrays. No migrated list has an
`idField`: repeated widget types, dividers and appearance variants are valid.

In the assigned test VM, from the delivered source tree:

```sh
python3 -B Scripts/dev/build-settings-schema.py
python3 -B Scripts/dev/build-settings-schema.py --check
python3 -B Scripts/dev/settings-schema-selftest.py --qml
```

Run these only through the task's authorized guest connector with disk-backed
TMPDIR and bounded commands. Generation emits actual `ConfigGroup`/`ConfigValue`
declarations, explicit legacy + 29 user shards, immutable reference defaults and
path-kind metadata. Nothing traverses the live settings facade. The checker
independently parses the old adapter's literal values, types and namespace
topology until that adapter is removed at cutover. Unknown syntax fails closed.

Every list, including nonempty lists, requires an overlay. Records validate
their declared fields while the library owns and preserves unknown JSON-shaped
members (including polymorphic widget payloads). Maps require one explicitly
typed element descriptor; no main-shell setting currently needs an open map.
Plugin schema maps are separately authored in the plugin milestone. `Any` is
not a descriptor. Integer fields preserve signed QML-int bounds; real fields
are explicitly reviewed even when a default is serialized as `1` or `0`.
Only existing closed contracts get enums, never extensible widget/color IDs.

The two historical QML `color` fields use String plus generated QColor grammar
from Qt 6.12's SVG names and 3/6/8/9/12-digit hex forms. ASCII case and space/tab
in names are retained; values are never normalized by the schema. QtGui-enabled
parity tests belong to application tooling, not configqml Core. QColor writers
and RGB display boundaries are adapted at cutover.

Construction inputs resolve HOME/avatar/wallpaper and system fonts before the
store starts. Reference defaults remain unpatched for tooltips/reset comparison;
`settingsVersion` is compatibility metadata (62), outside writable shard routes,
and is not configqml's durable schema version. Environment defaults are never
materialized as explicit user choices. These generated components are inert
until explicitly constructed; adding them does not switch the production owner.
