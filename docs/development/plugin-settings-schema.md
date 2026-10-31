# Plugin settings descriptor preparation

Plugin settings have a finite writable namespace. `metadata.settingsSchema` is an
additive descriptor authored alongside `metadata.defaultSettings` in the plugin's
manifest. It describes every public preference, including optional keys not in
defaults. It does not describe state/cache payloads or infer fields from user data.

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
Config-file deep merging is a separate namespace/descriptor responsibility.

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

The first reviewed slice is hello-world: all seven QML entrypoints reference only
`message`/`iconColor`, and it has no config.default.json or extra preference file.
Its new manifest declares both String leaves; the compatibility catalog covers
the frozen1.2.5 version. Descriptor metadata alone is additive and needs no new
runtime API, so this slice retains its existing minimum shell version. Map/cache/
receipt-dependent ports must declare their actual capability/release boundary.
The rest of the161-plugin catalog, runtime-key ports, page callbacks/dirty contracts
and config descriptors remain required I4 work.
