# keyd (macOS environment)

Hardware-level Alt↔Super swap and (planned) Cmd+Click mouse translation.

## Files

- `default.conf` — the *active* keyd configuration used when this environment is enabled.
  Deployed to `/etc/keyd/atmosphera` (an include file — no `[ids]` section) by
  `atmosphera-bindings-apply` (needs elevation).
- `atmosphera.stub` — neutral no-op version. Written to `/etc/keyd/atmosphera` at
  install time so keyd can run harmlessly before any environment is chosen.

## Install-time setup (root)

The installer (or the NixOS module) does the one-time bootstrap:

1. Write `/etc/keyd/default.conf` with an `[ids] *` block and `include atmosphera`
   (only if `default.conf` does not already exist — never clobber a user's config).
2. Write `/etc/keyd/atmosphera` from `atmosphera.stub` (neutral, no bindings).
3. Enable + start the keyd service.

After that, `atmosphera-bindings-apply` can swap the *content* of
`/etc/keyd/atmosphera` between the stub and `default.conf` based on the selected
environment. keyd reloads pick up the change.

## Panic sequence

If keyd renders the keyboard unusable, hold **Backspace + Escape + Enter**
simultaneously to force keyd to terminate.
