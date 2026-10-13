# Native metadata for QML tooling

Runtime modules are not a lint-input repair location. `qml-native-metadata.py`
selects a source-backed input family by the SHA-256 inventory of the installed
Quickshell descriptions, checks its complete artifact inventory and the matching
Qt metatype inputs reached by its generated contracts, and creates a private import
universe for ordinary `qmllint.sh`. Other installed modules remain unchanged.
An unknown family, missing reference, conflicting owner or altered artifact is
an error; diagnostic categories and severities are unchanged.

| # | Family | Source commit | Qt toolchain |
|---|---|---|---|
| 1 | `qt611-qs031` | `1a4716cde794a59928d9d9fc15f2afc7a95de360` (Quickshell 0.3.1) | 6.11.2 |
| 2 | `qt612-qs032` | `4f508be500dea6e5732cc3d50382a0048b17e7b1` (Quickshell 0.3.2) | 6.12.0 |

The manifests contain the exact source-archive checksums and inventories, not
version-name matching. Lint verifies both native and required Qt metadata before using
the generated contract. Run `python3 -B Scripts/dev/qml-native-metadata-selftest.py`
in the assigned VM: it exercises ownership/integrity and the ordinary lint
boundary's valid native properties, genuine property typo and ineffective
expression. The normal container hook uses this same metadata boundary.

## Producer contract

`quickshell-metadata-generate.py` uses a separate extracted original source,
patched candidate, CMake build and output directory. The producer patch makes
reflected pointers express their public metaobject interface and qualifies
namespace-local collections. The registration patch marks Polkit Identity
anonymous, retaining its real properties without introducing a public name;
it also registers source-declared native flag aliases with `Q_FLAG`/`Q_FLAG_NS`.

The recipe runs the native CMake/moc/registrar targets, then supplies all native
and Qt metatype inputs to each module's registrar. Module exports retain their
own ownership. A separate anonymous all-source inventory describes unregistered
metaobjects and classes from linked libraries; its exports are stripped before
foreign descriptions enter a consuming scope.

For an unreflected C++ template superclass, the native compiler emits an object
that takes the address of the inherited `staticMetaObject`. Its relocation
identifies the actual reflected base. A second compiler probe asserts identity
with that base. This works for native and Qt templates without a class-name
alias table, source-ancestry guess or runtime deployment. Native non-reflected
metatypes have source-backed `Q_DECLARE_METATYPE` provenance. Qt/builtin types
and reflected enum identities come from the matching installed toolchain's
descriptions. If the graph reaches an SDK enum lacking `Q_ENUM` (older Qt can
use these in reflected signals), the recipe locates its unique SDK metatype
owner/header and compiles `static_assert(std::is_enum_v<identity>)` against that
SDK. The terminal receipt binds the header and compiler probe hashes. It does
not fabricate reflected enum values or make an unregistered enum accessible
from QML. Unknown names and non-enum nested types still fail.

The closure materializer reconciles identical native descriptions, rejects
conflicting ones, resolves native inheritance, members, containers and enums
recursively, and rejects unknown references. C++ identities are never resolved
by a same-spelled public QML export.

## Regeneration

Use the immutable source commit/archive and matching Qt toolchain recorded in
the family's manifest. First regenerate the **unpatched** source and compare
every installed description byte-for-byte; a version label alone is insufficient
provenance. Run generation in the assigned project test VM, with a disk-backed
workspace and `TMPDIR`. For example, inside that VM:

```sh
timeout 1500s python3 -B Scripts/dev/quickshell-metadata-generate.py \
  --source "$WORKSPACE/original-source" \
  --candidate "$WORKSPACE/candidate-source" \
  --build "$WORKSPACE/candidate-build" \
  --output "$WORKSPACE/generated-inputs" \
  --installed "$QML_DIR/Quickshell" \
  --source-commit "$PINNED_COMMIT" \
  --source-archive "$SOURCE_ARCHIVE" \
  --source-archive-sha256 "$PINNED_ARCHIVE_SHA256"
```

For a privately extracted older Qt toolchain, set its `LD_LIBRARY_PATH` and pass
`--qt-prefix`, `--qt-metatypes` and `--registrar`. `--reuse-build` exports from a
retained verified candidate/build instead of repeating compilation. Preserve
the source/build trees, generated moc inputs, compiler probes, logs and receipts.
Do not install the candidate libraries or modify an upstream checkout.

The ordinary lint path requires the packaged descriptions, owner inventory,
terminal provenance and integrity manifest. Generation or closure diagnostics
alone do not prove full lint, cold load, consumer behavior or normal-hook success.
Package `Quickshell/`, `owners.qmltypes`, `terminals.json` and `manifest.json`
under a fresh family directory beside this document; keep `generation.json`
and all other producer/build evidence outside the repository. The manifest binds
every consumed artifact, the unmodified installed family, source archive, patches,
generator and actual native/Qt metatype inputs.
The full `qt_metatypes` inventory records producer provenance;
`required_qt_metatypes` is derived from every generated component identity and
type reference (including the anonymous owner inventory). Each reached SDK
owner must match at consumption time. Unrelated optional SDK packages can be
present or absent without changing this contract.
