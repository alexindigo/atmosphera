# Inert configqml model preparation

`Scripts/dev/fixtures/settings-model-adapters.qml` prepares the four selected
library-model boundaries. It is a disposable Quickshell entrypoint, copied to
the installed shell root by the VM driver. Production readers still use the old
Settings owner; nothing imports this fixture during normal startup.

| # | Future consumer | Adapter contract |
|---|---|---|
| 1 | Control-center cards | `listModel(["controlCenter", "cards"])`; scalar `model.id` and `model.enabled`, including weather gating. |
| 2 | Calendar cards | `listModel(["calendar", "cards"])`; same shared card adapter and scalar roles. |
| 3 | Media blacklist | `listModel(["audio", "mprisBlacklist"])`; primitive `modelData`; injected removal resolves the displayed value against the current owning leaf. |
| 4 | Desktop context menu | `listModel(["desktopContextMenu", "items"])`; scalar `model.id`; injected indexed removal carries a publication generation and refuses pending/stale generations. |

The generated `SettingsSchema` is the actual schema under test. Repeated card
IDs/dividers do not acquire a uniqueness constraint: these models are index-only.
A record's `modelData` is an immutable ConfigNode snapshot, not a record with a
writable `.id`. Model role writes must emit `read-only-model` without changing
the owner. No editor combines a model's old index with a newer property array.

The fixture checks generated defaults, weather gates, equal-length role updates,
reorder/shrink, retained-node ownership, all four role-write rejections, removal
by current value while model publication lags, and pending/stale/current menu
generation callbacks. It awaits worker receipts before checking the consumers
and closes the store before quitting. MemorySource proves worker/model behavior,
not filesystem persistence or full-shell timing.

Run only in the assigned integration VM (agora VM804), with disk-backed TMPDIR
and a bounded `qs -p <installed-root>/settings-model-adapters.qml` process. The
success marker is `I4_MODEL_ADAPTERS: PASS`; a timeout or missing endpoint is a
failure. Run the project qmllint script and the normal cold-shell gate as well.
