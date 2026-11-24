{ lib, stdenv, cmake, ninja, qt6, fetchFromGitHub, configqmlSrc ? fetchFromGitHub {
    owner = "alexindigo";
    repo = "configqml";
    # Published release source: 09dfa03ff3c1af0ee655b1be97d7585b97c95477.
    rev = "v0.5.5";
    hash = "sha256-NQSFMsfQM26n8iPXjZY1oksV8CdR2WKxKFHST/T9HxA=";
  }
}:
stdenv.mkDerivation {
  pname = "qt6-configqml";
  version = "0.5.5";
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
