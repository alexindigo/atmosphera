# Evaluate the real package recipe without fetching/building Nixpkgs or Qt.
# Dependency values are sentinels; this proves assembly, not a Nix runtime build.
{ calendarSupport ? false, waylandPrefix ? "/usr" }:
let
  package = import ../../../nix/package.nix;
  prefix = "/usr";
  lib = rec {
    optional = condition: value: if condition then [ value ] else [ ];
    optionalString = condition: value: if condition then value else "";
    path.hasPrefix = a: b:
      let text = toString a; in builtins.substring 0 (builtins.stringLength text) (toString b) == text;
    cleanSourceWith = { src, filter }: builtins.path {
      path = src;
      name = "atmosphera-assembly-source";
      filter = name: type: builtins.baseNameOf name != ".git" && filter name type;
    };
    makeSearchPath = directory: packages: builtins.concatStringsSep ":" (map (p: "${p}/${directory}") packages);
    makeBinPath = makeSearchPath "bin";
    makeLibraryPath = makeSearchPath "lib";
    licenses.gpl3Only = "GPL-3.0-only";
  };
  qt = { outPath = prefix; qtQmlPrefix = "lib/qt6/qml"; __toString = self: self.outPath; };
  derivation = package {
    inherit lib calendarSupport;
    stdenvNoCC.mkDerivation = attributes: attributes;
    qt6 = { qtbase = qt; wrapQtAppsHook = "qt-wrapper-hook"; qtmultimedia = prefix; qtimageformats = prefix; };
    quickshell = "/dependencies/quickshell";
    configqml = prefix;
    brightnessctl = prefix; cliphist = prefix; ddcutil = prefix; wlsunset = prefix;
    wl-clipboard = prefix; wlr-randr = prefix; imagemagick = prefix; wget = prefix;
    wayland-scanner = prefix;
    wayland = waylandPrefix;
    python3.withPackages = select: "/dependencies/python-" + builtins.concatStringsSep "-" (select {
      pygobject3 = "pygobject3"; dbus-python = "dbus-python";
    });
    evolution-data-server = prefix; libical = prefix; glib = qt // { out = prefix; };
    libsoup_3 = prefix; json-glib = prefix; gobject-introspection = prefix;
  };
in {
  inherit (derivation) installPhase preFixup;
  src = toString derivation.src;
}
