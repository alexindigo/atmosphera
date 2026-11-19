{ lib, stdenv, cmake, ninja, qt6, fetchFromGitHub, configqmlSrc ? fetchFromGitHub {
    owner = "alexindigo";
    repo = "configqml";
    # Published release source: b50ccafbd990d6049b846bc4654890126d24506c.
    rev = "v0.5.1";
    hash = "sha256-U6NKYqJXv2xmOZVnvLDjXUByrVTtJH9ZlMEr9RIrjuE=";
  }
}:
stdenv.mkDerivation {
  pname = "qt6-configqml";
  version = "0.5.1";
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
