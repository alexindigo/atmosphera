{
  description = "Noctalia shell - a Wayland desktop shell built with Quickshell";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    systems,
    quickshell,
    ...
  }: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    formatter = eachSystem (
      system:
        nixpkgs.legacyPackages.${system}.alejandra
    );
    packages = eachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        qs = quickshell.packages.${system}.default.override {
          withX11 = false;
          withI3 = false;
        };
        
        # Custom ttf-bootstrap-icons package
        ttf-bootstrap-icons = pkgs.stdenvNoCC.mkDerivation rec {
          pname = "ttf-bootstrap-icons";
          version = "1.13.1";
          
          src = pkgs.fetchzip {
            url = "https://github.com/twbs/icons/releases/download/v${version}/bootstrap-icons-${version}.zip";
            sha256 = "999021e12fab5c9ede5e4e7072eb176122be798b2f99195acf5dda47aef8fc93";
            stripRoot = false;
          };
          
          installPhase = ''
            runHook preInstall
            install -Dm644 fonts/bootstrap-icons.ttf $out/share/fonts/truetype/bootstrap-icons.ttf
            runHook postInstall
          '';
          
          meta = with pkgs.lib; {
            description = "Official open source SVG icon library for Bootstrap";
            homepage = "https://icons.getbootstrap.com/";
            license = licenses.mit;
            platforms = platforms.all;
            maintainers = [];
          };
        };
        
        runtimeDeps = with pkgs; [
          bash
          bluez
          brightnessctl
          cava
          cliphist
          coreutils
          ddcutil
          file
          findutils
          gpu-screen-recorder
          libnotify
          matugen
          networkmanager
          wl-clipboard
        ];
        fontconfig = pkgs.makeFontsConf {
          fontDirectories = [
            pkgs.material-symbols
            pkgs.roboto
            pkgs.inter-nerdfont
            ttf-bootstrap-icons  # Add the custom font package here
          ];
        };
      in {
        default = pkgs.stdenv.mkDerivation {
          pname = "noctalia-shell";
          version = self.rev or self.dirtyRev or "dirty";
          src = ./.;
          nativeBuildInputs = [pkgs.gcc pkgs.makeWrapper pkgs.qt6.wrapQtAppsHook];
          buildInputs = [qs pkgs.xkeyboard-config pkgs.qt6.qtbase];
          propagatedBuildInputs = runtimeDeps;
          installPhase = ''
            mkdir -p $out/share/noctalia-shell
            cp -r ./* $out/share/noctalia-shell
            makeWrapper ${qs}/bin/qs $out/bin/noctalia-shell \
              --prefix PATH : "${pkgs.lib.makeBinPath runtimeDeps}" \
              --set FONTCONFIG_FILE "${fontconfig}" \
              --add-flags "-p $out/share/noctalia-shell"
          '';
          meta = {
            description = "A sleek and minimal desktop shell thoughtfully crafted for Wayland, built with Quickshell.";
            homepage = "https://github.com/noctalia-dev/noctalia-shell";
            license = pkgs.lib.licenses.mit;
            mainProgram = "noctalia-shell";
          };
        };
        
        # Expose the custom font as a separate package (optional)
        ttf-bootstrap-icons = ttf-bootstrap-icons;
      }
    );
    defaultPackage = eachSystem (system: self.packages.${system}.default);
  };
}