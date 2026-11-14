{ lib, stdenv, cmake, ninja, qt6, fetchFromGitHub, configqmlSrc ? fetchFromGitHub {
    owner = "alexindigo";
    repo = "configqml";
    # Pre-release pin; replace with the published v0.5.0 archive at acceptance.
    rev = "a3240f2dbc9adae2ea51e89b3fa5ca5f53b23055";
    hash = "sha256-mI5VAMR8hnXAASKn4P54NDX7nblhSTCweVF7nmU2OEA=";
  }
}:
stdenv.mkDerivation {
  pname = "qt6-configqml";
  version = "0.5.0";
  # Avoid callPackage auto-injecting nixpkgs.src instead of this pinned source.
  src = configqmlSrc;
  nativeBuildInputs = [ cmake ninja qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative ];
  cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
  dontWrapQtApps = true;
  # The private-metaobject adapter checks exact Core/CorePrivate/Qml versions.
  # Using this same qt6 set for Quickshell and configqml is mandatory.
  meta = {
    description = "Worker-owned layered configuration for Qt and QML";
    homepage = "https://github.com/alexindigo/configqml";
    license = lib.licenses.lgpl3Plus;
    platforms = lib.platforms.linux;
  };
}
