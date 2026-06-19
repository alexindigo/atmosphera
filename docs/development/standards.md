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

### pre-push
Rejects unsigned commits and tags. Enable signing:

```sh
git config commit.gpgSign true
git config tag.gpgSign true
git config gpg.format ssh
git config user.signingkey "$(cat ~/.ssh/id_ed25519.pub)"
```

### Lefthook (optional)

`lefthook.yml` adds pre-commit hooks for QML formatting and settings index rebuild. Install [lefthook](https://github.com/evilmartians/lefthook#install) and run `lefthook install` to enable.

## Making Changes

1. Fork and clone the repo
2. Run `nix develop` or install dependencies manually
3. Make your changes
4. Run `./Scripts/dev/qmlfmt.sh` to format QML
5. Commit with a signed commit: `git commit -S -m "fix: description"`
6. Push and open a pull request

## Upstream Patches

Upstream fixes ported to our fork live in `patches/` and are applied via `Scripts/dev/apply-patch.sh`. See `patches/README.md` for workflow details.
