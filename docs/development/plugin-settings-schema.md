# Plugin settings descriptor preparation

Plugin settings have a finite writable namespace. `metadata.settingsSchema` is an
additive descriptor authored alongside `metadata.defaultSettings` in the plugin's
manifest. It describes every public preference, including optional keys not in
defaults. Existing finite content/session-state writers remain declared atomic
leaves for this integration, marked `machineLocal` (and `sensitive` for tokens).
They are excluded from profiles, not silently removed from the writable API.
The mawaqit dynamic calendar cache has its own cache owner. No schema is inferred
from user files.

```json
{
  "version": 1,
  "fields": {
    "message": {"type": "String"},
    "optionalLabel": {"type": "String", "optional": true}
  }
}
```

The format reuses the main schema overlay's typed descriptors and optional
`definitions`/`ref` entries. Every top-level setting is an atomic leaf: records,
lists and maps retain the plugin API's existing shallow replacement semantics.
Groups are not allowed inside settings descriptors. Collection element types must
be explicit, even for empty defaults. Optional fields without defaults stay absent;
no missing choice is materialized. Record payloads retain owned unknown members
under configqml's normal checked admission. Extensible string IDs are not enums.
Config-file deep merging is a separate namespace/descriptor responsibility:
`metadata.configSchema` uses the same format, allowing explicit `Group` namespaces
and atomic collection/record leaves. The compiler requires the separately authored
`config.default.json` as `--config-defaults` with `--namespace config`. Missing
optional config leaves remain absent. A group is not an atomic record or a list;
it accepts namespace flags, not leaf constraints. The frozen/current 161-plugin
catalog contains no config.default.json files or config consumers, so it has no
config compatibility entries. The synthetic deep-config witness covers this API
without fabricating schemas for arbitrary user override files.

`Configs/plugin-settings-overlays.json` supplies descriptors for reviewed **exact**
old plugin id/version pairs. It never guesses a schema for an unknown version.
An authored manifest descriptor takes precedence; an invalid one cannot fall back
to older metadata. Unknown raw user data is retained by the file owner rather
than exposed as an admitted dynamic property. A descriptor cannot make an old
plugin's arbitrary root-key creation compatible: those plugins must be ported to
a map or state/cache owner and diagnosed explicitly until then.

The inert `Scripts/dev/build-plugin-settings-schema.py` validates metadata and
emits a ConfigSchema using the existing main-schema declaration emitter. It reads
only the selected manifest and host metadata, never user settings. This is build/
test preparation; it does not switch the production plugin owner. I5 constructs
each lazy per-plugin store from the selected immutable descriptor, with the actual
source/fallback/lifecycle contract. Do not treat descriptor presence as proof of
complete caller/schema compatibility without the catalog audit.

The compatibility catalog covers the frozen exact versions of all 159 finite
plugins. Each descriptor was compiled against that version's original authored
defaults, with the frozen manifest hash checked. The mawaqit 1.3.8 and
video-wallpaper 2.0.11 arbitrary-root-key runtimes deliberately have no finite
overlay. An unknown id/version without authored metadata still fails closed.
Authored current descriptors retain their own flags and optional fields.

### Source-only compatibility metadata

`metadata.settingsSourceProjection` format 1 has exactly `version`, `projectionId`
and a standalone function-source string `transform`. The companion compiler
`compile_projection(manifest, overlays, source_ids)` emits a native
`ConfigProjection` component. Its caller supplies the actual distinct declared
source IDs before store construction. The CLI uses `--projection-output` plus one
`--source-id` per participating source. There are no guessed source names, GUI
evaluation, Effective transforms or source reads in the compiler. Native worker
construction validates/executes the authored source and result protocol.

The old Screen Toolkit exact version also selects the nonpersisting empty-string
palette projection. `sourceProjections` is a separate exact-version catalog from
settings descriptors. Authored projection metadata takes precedence and malformed
metadata cannot select an older transform. Source fallback continues to be the
worker's whole-source `fallbackFor` policy, not a field-level projection fallback.

`runtime_compatibility` and CLI `--require-runtime-compatible` expose the explicit
`incompatible` exact-version gate. Both old/new video-wallpaper preparatory
versions, old mawaqit, and both shell-profiles versions require their corresponding
runtime port. A present descriptor or successful inert compile does not make those
new-owner runtime paths compatible. Files are retained on diagnosis. The current
old production loader is unchanged: I5 must enforce this gate when constructing
the new owners and lift entries only alongside the actual coupled runtime port.
No transitional projection loader has been added.

### Verification boundary

`plugin-settings-contract-regression.py --plugins CATALOG --frozen-plugins FROZEN
--output OUT --work-root WORK` runs in the assigned VM. It cold-constructs the
installed library with all 161 authored descriptors and 159 exact old overlays,
observes actual scalar bindings, and tests rejecting controls. It exercises the
exact generated Source components through whole-source presence, acknowledged
save and separate cold-restart consumers, preserving read-only legacy identity
and unknown writable data. A separate explicit deep-config case checks group
merge/list replacement, sparse persistence and absent optional fields.

These are inert compiler/library witnesses. Plugin page receipt/current-refresh,
dirty contracts, normalized-list callers and the coupled I5 video/profile product
ports retain their own required consumer verification. Descriptor preparation
does not prove those runtime paths.
