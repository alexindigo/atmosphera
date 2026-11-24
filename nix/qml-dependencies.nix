{ stdenv, lib, fetchurl, cmake, ninja, pkg-config, patchelf, qt6, pipewire }:
let
  # Match the released source pins used by the dev tooling image. All modules
  # are built against the same Qt set as Quickshell and ConfigQml.
  module = { name, version, sha256, extraInputs ? [ ] }: stdenv.mkDerivation {
    pname = "qt6-${name}";
    inherit version;
    src = fetchurl {
      url = "https://github.com/alexindigo/${name}/archive/refs/tags/v${version}.tar.gz";
      inherit sha256;
    };
    nativeBuildInputs = [ cmake ninja pkg-config patchelf qt6.wrapQtAppsHook ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative ] ++ extraInputs;
    cmakeFlags = [ "-DBUILD_TESTING=OFF" "-DBUILD_TEST_MODE=OFF" "-DCMAKE_INSTALL_LIBDIR=lib" ];
    dontWrapQtApps = true;
    postInstall = ''
      # Released modules with a distro-style hard-coded Qt directory must join
      # the Nix Qt module prefix, not an incidental Arch QML_IMPORT_PATH.
      if [ -d "$out/lib/qt6/qml" ] && [ "lib/qt6/qml" != "${qt6.qtbase.qtQmlPrefix}" ]; then
        mkdir -p "$(dirname "$out/${qt6.qtbase.qtQmlPrefix}")"
        mv "$out/lib/qt6/qml" "$out/${qt6.qtbase.qtQmlPrefix}"
        rmdir "$out/lib/qt6"
      fi
      # Those releases copy the build's QML directory, including plugin ELF
      # files, rather than install(TARGETS) them. Replace build-tree lookup with
      # the installed core library while preserving the actual Qt dependencies.
      while IFS= read -r -d $'\0' plugin; do
        IFS=: read -ra paths <<< "$(patchelf --print-rpath "$plugin")"
        rpath="$out/lib"
        for entry in "''${paths[@]}"; do
          case "$entry" in "$NIX_BUILD_TOP"/*|"") ;; *) rpath="$rpath:$entry" ;; esac
        done
        patchelf --set-rpath "$rpath" "$plugin"
      done < <(find "$out/${qt6.qtbase.qtQmlPrefix}" -type f -name '*.so' -print0)
    '';
    meta.platforms = lib.platforms.linux;
  };
in {
  dbusqml = module {
    name = "dbusqml"; version = "1.1.2";
    sha256 = "00c7ec63c3407a53c0b43c5bfdec81f1a3f23f71aa757fab97ba24dacd2d7681";
  };
  xdgiconqml = module {
    name = "xdgiconqml"; version = "0.1.0";
    sha256 = "4017958aaba9791e5799fc72ae8447ed0db4026de741ade50e4e94abe5b955e9";
  };
  pipewirespectrum = module {
    name = "pipewirespectrum"; version = "0.1.0";
    sha256 = "9c1be44521c2386f7a2190e6ca07b9eec692c4ed765faa29331ea4815d080544";
    extraInputs = [ pipewire ];
  };
  niriqml = module {
    name = "niriqml"; version = "0.2.0";
    sha256 = "59079deeeed8dc245e35ee91846f0f7b32e005cc6ff716a1b05ed68de64e0b4f";
  };
  mangowcqml = module {
    name = "mangowcqml"; version = "0.1.0";
    sha256 = "1e92e9ec4e7b274b2c0a4e28ee377cc08c026f1c364d6e1a66b62576578dc7b8";
  };
}
