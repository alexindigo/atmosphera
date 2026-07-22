# Atmosphera — Development

## QML Linting

Run the qmllint script against changed QML files before committing:

```
Scripts/dev/qmllint.sh Modules/Panels/Settings/Tabs/Idle/
```

Or lint the entire tree:

```
Scripts/dev/qmllint.sh
```

The script uses Qt6's qmllint (requires `qt6-declarative-tools` on Arch, or
`qt6-tools-dev-tools` on Ubuntu). Version 6.6 or later is recommended for
full error-detection support.

Severity levels are configured in `.qmllint.ini` at the repo root:
- `missing-property`, `unresolved-type`, `missing-type` → error (blocks commit)
- `unqualified-id` → disabled (noisy with custom `qs.*` module references)
- `import` → info (custom modules lack qmltypes)

## Pre-commit Hook

A tracked pre-commit hook lives at `.githooks/pre-commit`. It runs `qmlformat`
and `qmllint` on staged QML files, blocking commits with lint errors.

To activate it on your clone (one-time setup):

```
git config core.hooksPath .githooks
```

To restore default behavior (use `.git/hooks/` instead):

```
git config --unset core.hooksPath
```

## Cold-Load Smoke Test

After any QML change, verify the shell loads from a cold start:

```
qs -c atmosphera -d
```

Expect exit code 0. Live-reload testing alone is insufficient — it lazy-loads
modules and can miss parser errors that trigger only on a fresh start.

## Formatting

```
Scripts/dev/qmlfmt.sh
```

Uses `qmlformat` with 2-space indent and 360-character line width.
