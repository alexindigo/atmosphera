# Portals TODO

## Near-term

- [ ] **Wire SettingsPortal.qml to D-Bus library** — replace stubs with real DBusMethod/DBusSignal calls once the library API stabilizes
- [ ] **Register org.freedesktop.impl.portal.atmosphera** on the session bus and serve Read/ReadAll methods at `/org/freedesktop/portal/desktop`
- [ ] **Emit SettingChanged** on dark/light toggle so listening apps update live
- [ ] **Add portal files to the AUR PKGBUILD** — all `.portal` files need to be installed to `/usr/share/xdg-desktop-portal/portals/`. The `package()` function should copy them there.
- [ ] **Add portal files to the nix package** — same for `nix/package.nix`
- [ ] **Automatic priority** — figure out a way to write `portals.conf` on first launch (or at install time) so the user doesn't need to do it manually. Options: shell init script, post-install hook in PKGBUILD, or write it lazily when SettingsPortal starts up.

## Future

- [ ] FileChooser portal — open files from sandboxed apps, integrating with the shell's file picker
- [ ] Screenshot portal — share screen/region selection, integrate with the recorder
- [ ] RemoteDesktop/Wayland portal — pointer/keyboard/keyboard grab for remote desktop apps
- [ ] **Plugin support** — allow user plugins to claim portal D-Bus names to override built-in backends. Each `.portal` file declares a D-Bus name; if a plugin registers the same name, it takes over that interface automatically. Document the pattern in `Compat/README.md`.
