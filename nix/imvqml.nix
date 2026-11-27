{ lib, stdenv, fetchurl, cmake, ninja, pkg-config, qt6, kdePackages, makeWrapper, vips, libwebp, mpv-unwrapped }:
let
  readers = [ qt6.qtimageformats kdePackages.kimageformats ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "qt6-imvqml";
  version = "0.1.5";
  src = fetchurl {
    url = "https://codeload.github.com/alexindigo/imvqml/tar.gz/refs/tags/v${finalAttrs.version}";
    sha256 = "59cc363fa25b52e860148b1c113c1c321efe339dde07a4242ceeae1022f13ca3";
  };
  nativeBuildInputs = [ cmake ninja pkg-config makeWrapper ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative vips libwebp mpv-unwrapped ] ++ readers;
  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_INSTALL_LIBDIR=lib"
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
      --prefix QT_PLUGIN_PATH : '${lib.makeSearchPath qt6.qtbase.qtPluginPrefix readers}'
  '';
  meta.platforms = lib.platforms.linux;
})
