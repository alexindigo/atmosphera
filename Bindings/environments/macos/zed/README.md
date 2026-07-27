# Zed (macOS environment)

macOS keymap for the Zed editor: Cmd for save/undo/find/copy/paste, arrows for
line/document navigation, Option for word navigation, plus terminal-context
forwarding.

## Files

- `keymap.json` — deployed to `~/.config/zed/keymap.json`.

## Notes

Zed does not merge multiple keymap files. If you have an existing
`~/.config/zed/keymap.json`, `atmosphera-bindings-apply` will back it up to
`keymap.json.pre-atmosphera` before overwriting.
