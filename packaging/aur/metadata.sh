depends=(
  'quickshell'
  'qt6-dbusqml>=1.1.0'
  'qt6-pipewirespectrum'
  'qt6-xdgiconqml-git'
  'imagemagick'
  'brightnessctl'
  'ffmpeg'
  'qt6-multimedia'
  'python'
  'python-dbus'
  'python-gobject'
  'wlr-randr'
)
optdepends=(
  'cliphist: For clipboard history support'
  'wlsunset: For supporting NightLight'
  'power-profiles-daemon: For power profile management'
  'ddcutil: For external display brightness control'
  'qt6-niriqml: niri IPC integration (workspaces, windows, session config)'
  'qt6-mangowcqml: mangowc IPC integration (workspaces, windows, session config)'
  'keyd: hardware-level keyboard remapping (bindings environments)'
  'xremap-niri-bin: session-level app-scoped keymaps (macos bindings)'
  'qt6-5compat: required by some registry plugins (e.g. cookie-clock)'
  'qt6-websockets: required by some registry plugins (e.g. hassio)'
  'xdg-desktop-portal-gnome: screencast / screen-sharing support (niri cannot use -wlr)'
)
provides=('atmosphera' 'xdg-desktop-portal-impl')
