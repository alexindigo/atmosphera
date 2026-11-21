# Standards & Architecture

## Code Standards

- **No Qt5Compat** — use modern Qt6 alternatives (`QtQuick.Effects`, `MultiEffect`)
- **Use `Logger.qml`** for logging instead of `console.log`
- **Follow existing patterns** — study similar features before implementing new ones
- **Test with both Niri and Hyprland** where applicable
- **Small, focused PRs** are preferred

## Architecture Principles

### Service-First
Implement logic in services, keep UI components lightweight and focused on presentation. Services are Singletons in `Services/`, UI components go in `Modules/`.

### Widget Reusability
Check `Widgets/` before creating new ones. `N*` prefixed widgets (NButton, NTextInput, NIcon, etc.) are our custom components.

### Error Handling
Use the Logger singleton:
- `Logger.i(tag, message)` — info (always shown)
- `Logger.e(tag, message)` — error (always shown)
- `Logger.d(tag, message)` — debug (requires `ATMOSPHERA_DEBUG=1`)

## Git Hooks

### pre-commit (tracked, normal validation)

The tracked hook at `.githooks/pre-commit` is a quick sanity check. It formats
and restages staged QML inside the dev container (rootless Podman or Docker),
checks changed-plugin compatibility, then checks final-index schema/search
freshness and built-in settings-store compatibility. It rejects invalid inputs
without silently regenerating settings resources. Enable once per clone with
`git config core.hooksPath .githooks`.

Full QML lint/canaries, detached-settings-write analysis and settings regressions
belong in CI. Settings, QML and plugin workflows run on every PR, whatever the
base branch, and pushes to `main`. No check moved from the hook is omitted.
See DEVELOPMENT.md, "Pre-commit Hook", for engine prerequisites, deadlines and
commands to run the full suite inside the assigned test VM.

### pre-push
The optional Lefthook pre-push jobs reject untrusted remotes and unsigned commits
and tags; these duties are unchanged. Enable signing:

```sh
git config commit.gpgSign true
git config tag.gpgSign true
git config gpg.format ssh
git config user.signingkey "$(cat ~/.ssh/id_ed25519.pub)"
```

### Lefthook (optional, historical)

`lefthook.yml` predates the tracked hook and remains only as optional advice
for contributors who prefer that tool. It adds pre-commit hooks for QML
formatting (staged QML only) and settings index rebuild, using the container.
Install [lefthook](https://github.com/evilmartians/lefthook#install) and run
`lefthook install` to enable. It is not a substitute for the tracked hook's
final-index sanity checks or CI's full suite.

## Making Changes

1. Fork and clone the repo
2. Run `nix develop` or install dependencies manually
3. Make your changes
4. Run `./Scripts/dev/qmlfmt.sh` to format QML
5. Commit with a signed commit: `git commit -S -m "fix: description"`
6. Push and open a pull request

## Upstream Patches

Upstream fixes ported to our fork live in `patches/` and are applied via `Scripts/dev/apply-patch.sh`. See `patches/README.md` for workflow details.
