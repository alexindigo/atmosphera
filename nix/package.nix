{
  version ? "dirty",
  extraPackages ? [ ],
  # Optional QtPdf renderer for PDF preview in the file chooser.
  pdfPreviewSupport ? false,
  runtimeDeps ? [
    quickshell
    brightnessctl
    cliphist
    ddcutil
    wlsunset
    wl-clipboard
    wlr-randr
    wget
    glib # gio trash implements the freedesktop Trash specification
    # The real logind delay-inhibitor fd needs both bindings, independently of
    # optional calendar integration.
    (python3.withPackages (pp: [ pp.dbus-python pp.pygobject3 ]))
  ],

  lib,
  stdenvNoCC,
  # build
  qt6,
  quickshell,
  configqml,
  dbusqml,
  xdgiconqml,
  pipewirespectrum,
  niriqml,
  mangowcqml,
  mpvqml,
  imvqml,
  # runtime deps
  brightnessctl,
  cliphist,
  ddcutil,
  wlsunset,
  wl-clipboard,
  wlr-randr,
  coreutils,
  systemd,
  wget,
  python3,
  wayland,
  wayland-scanner,
  # calendar support
  calendarSupport ? false,
  evolution-data-server,
  libical,
  glib,
  libsoup_3,
  json-glib,
  gobject-introspection,
}:
let
  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      !(builtins.any (prefix: lib.path.hasPrefix (../. + prefix) (/. + path)) [
        /.github
        /.gitignore
        /Assets/Screenshots
        /Scripts/dev
        /nix
        /LICENSE
        /README.md
        /flake.nix
        /flake.lock
        /shell.nix
        /lefthook.yml
        /CLAUDE.md
        /CREDITS.md
        /THIRD-PARTY-NOTICES.md
      ]);
  };

  # Source acquisition, originals and shell-owner discovery are required even
  # when the caller replaces runtimeDeps. ImvQml owns decoding and its helper.
  requiredTools = [
    python3
    coreutils # dispatcher path resolution and bounded shell-owner calls
    systemd # busctl used by shell-owner discovery
  ];

  giTypelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    evolution-data-server
    libical
    glib.out
    libsoup_3
    json-glib
    gobject-introspection
  ];
in
stdenvNoCC.mkDerivation {
  pname = "atmosphera";
  inherit version src;

  nativeBuildInputs = [
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    configqml
    dbusqml
    xdgiconqml
    pipewirespectrum
    niriqml
    mangowcqml
    mpvqml
    imvqml
    qt6.qtbase
    qt6.qtmultimedia
  ] ++ lib.optional pdfPreviewSupport qt6.qtwebengine;

  installPhase = ''
    mkdir -p $out/share/atmosphera $out/bin
    cp -r . $out/share/atmosphera

    # Named `qs -c` configs resolve XDG_CONFIG_DIRS, not QS_CONFIG_PATH.
    mkdir -p $out/etc/xdg/quickshell
    ln -s ../../../share/atmosphera $out/etc/xdg/quickshell/atmosphera
    bash Scripts/bash/install-locker-configs "$PWD" "$out/etc/xdg/quickshell"

    # atmosphera-ipc — raw IPC entry point (stays as a symlink to qs)
    ln -s ${quickshell}/bin/qs $out/bin/atmosphera-ipc

    # xdg-desktop-portal backend manifest (Settings interface served in-shell)
    install -Dm644 Portals/atmosphera.portal $out/share/xdg-desktop-portal/portals/atmosphera.portal

    # Supervised shell as a systemd user service (activated per compositor
    # via `atmosphera setup <wm>`, never force-enabled)
    install -Dm644 Scripts/systemd/atmosphera.service $out/share/systemd/user/atmosphera.service
    install -Dm644 Scripts/systemd/hyprland-session.target $out/share/systemd/user/hyprland-session.target
  '';

  preFixup = ''
    qtWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath (runtimeDeps ++ extraPackages ++ requiredTools)}
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ wayland ]}
      --prefix XDG_DATA_DIRS : ${wayland-scanner}/share
      --set-default QS_CONFIG_PATH "$out/share/atmosphera"
      --set-default XDG_CONFIG_DIRS /etc/xdg
      --prefix XDG_CONFIG_DIRS : "$out/etc/xdg"
      --prefix QML_IMPORT_PATH : ${configqml}/${qt6.qtbase.qtQmlPrefix}
      --prefix QML_IMPORT_PATH : ${mpvqml}/${qt6.qtbase.qtQmlPrefix}
      --prefix QML_IMPORT_PATH : ${imvqml}/${qt6.qtbase.qtQmlPrefix}
      ${lib.optionalString calendarSupport "--prefix GI_TYPELIB_PATH : ${giTypelibPath}"}
    )
  '';

  # The automatic hook wraps ELF files only, not our shell dispatcher. Point
  # at its installed, unchanged basename so multi-call dispatch still works.
  postFixup = ''
    makeQtWrapper "$out/share/atmosphera/Scripts/bash/atmosphera" "$out/bin/atmosphera"
  '';

  meta = {
    description = "Atmosphera - a customizable desktop shell for Niri and Hyprland, built with Quickshell";
    homepage = "https://github.com/atmosphera-dev/atmosphera";
    license = lib.licenses.gpl3Only;
    mainProgram = "atmosphera";
  };
}
