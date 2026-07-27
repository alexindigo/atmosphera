# xremap (macOS environment)

User-level key remapping: modmap for the laptop keyboard bottom row, and keymaps
for text navigation, word navigation, terminal fixes, and app switching.

## Files

- `atmosphera-xremap.yml` — deployed to `~/.config/xremap/atmosphera-xremap.yml`.

## Service

xremap runs as a systemd user service. `atmosphera-bindings-apply` writes the config
but does not manage the service — enable it once with:

    systemctl --user enable --now xremap

Requires `xremap` built with a niri backend (e.g. `xremap-niri-bin` on AUR).

## Coupling to keyd

If keyd is also enabled, keyd handles the hardware modifier swap and xremap should
target keyd's virtual keyboard (`keyd virtual keyboard`). Adjust the `device.only`
selector in `atmosphera-xremap.yml` accordingly.
