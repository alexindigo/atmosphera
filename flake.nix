{
  description = "Noctalia shell - a Wayland desktop shell built with Quickshell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = {
    self,
    nixpkgs,
    systems,
    ...
  }: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = eachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [self.overlays.default];
      in {
        default = pkgs.noctalia-shell;
      }
    );

    overlays = {
      default = final: prev: {
        noctalia-shell = final.callPackage ./nix/package.nix {
          version = let
            mkDate = longDate: final.lib.concatStringsSep "-" [
              (builtins.substring 0 4 longDate)
              (builtins.substring 4 2 longDate)
              (builtins.substring 6 2 longDate)
            ];
          in
            mkDate (self.lastModifiedDate or "19700101")
            + "_"
            + (self.shortRev or "dirty");
        };
      };
    };

    devShells = eachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.callPackage ./nix/shell.nix {};
      }
    );

    homeModules.default = {
      pkgs,
      lib,
      ...
    }: {
      imports = [./nix/home-module.nix];
      programs.noctalia-shell.package =
        lib.mkDefault
        self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      programs.noctalia-shell.app2unit.package =
        lib.mkDefault
        nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.app2unit;
    };

    nixosModules.default = {
      pkgs,
      lib,
      ...
    }: {
      imports = [./nix/nixos-module.nix];
      services.noctalia-shell.package =
        lib.mkDefault
        self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
  };
}
