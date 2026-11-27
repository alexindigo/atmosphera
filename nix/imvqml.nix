{ lib, stdenv, fetchurl, cmake, ninja, pkg-config, qt6, kdePackages, makeWrapper, vips, libwebp, mpv-unwrapped }:
let
  readers = [ qt6.qtimageformats kdePackages.kimageformats ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "qt6-imvqml";
  version = "0.1.6";
  src = fetchurl {
    name = "imvqml-${finalAttrs.version}.tar.gz";
    url = "https://codeload.github.com/alexindigo/imvqml/tar.gz/refs/tags/v${finalAttrs.version}";
    sha256 = "7170c4448634d49edd51c2d4238491e334d637fa10a7a97b4ed1d0ae6ebd02b3";
  };
  nativeBuildInputs = [ cmake ninja pkg-config makeWrapper ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative vips libwebp mpv-unwrapped ] ++ readers;
  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_LIBEXECDIR=libexec"
    # Qt's relocatable install paths can escape the Nix store. Keep the
    # absolute dependency paths supplied by the Nix linker wrapper instead.
    "-DCMAKE_SKIP_INSTALL_RPATH=ON"
    "-DIMV_MPV_RUNTIME_HINT=${lib.getLib mpv-unwrapped}/lib/libmpv.so.2"
  ];
  dontWrapQtApps = true;
  postInstall = ''
    if [ "lib/qt6/qml" != "${qt6.qtbase.qtQmlPrefix}" ]; then
      mkdir -p "$(dirname "$out/${qt6.qtbase.qtQmlPrefix}")"
      mv "$out/lib/qt6/qml" "$out/${qt6.qtbase.qtQmlPrefix}"
    fi
  '';
  postFixup = ''
    wrapProgram "$out/libexec/imvqml-decoder" \
      --set QT_PLUGIN_PATH '${lib.makeSearchPath qt6.qtbase.qtPluginPrefix ([ qt6.qtbase ] ++ readers)}'
  '';
  meta.platforms = lib.platforms.linux;
})
