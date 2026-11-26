{ lib, stdenv, fetchurl, cmake, ninja, pkg-config, qt6, vips, libwebp, mpv-unwrapped }:
stdenv.mkDerivation (finalAttrs: {
  pname = "qt6-imvqml";
  version = "0.1.2";
  src = fetchurl {
    url = "https://codeload.github.com/alexindigo/imvqml/tar.gz/refs/tags/v${finalAttrs.version}";
    sha256 = "bc489d880373ede34064bb8d54a4757d9963cb72d5d32a072056230d02ffe071";
  };
  nativeBuildInputs = [ cmake ninja pkg-config qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative vips libwebp mpv-unwrapped ];
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
  meta.platforms = lib.platforms.linux;
})
