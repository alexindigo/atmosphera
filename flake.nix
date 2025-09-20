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

  outputs =
    {
      self,
      nixpkgs,
      systems,
      quickshell,
      ...
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

      packages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          qs = quickshell.packages.${system}.default.override {
            withX11 = false;
            withI3 = false;
          };

          runtimeDeps =
            with pkgs;
            [
              bash
              bluez
              brightnessctl
              cava
              cliphist
              coreutils
              ddcutil
              file
              findutils
              libnotify
              matugen
              networkmanager
              wlsunset
              wl-clipboard
            ]
            ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [ gpu-screen-recorder ];

          fontconfig = pkgs.makeFontsConf {
            fontDirectories = [
              pkgs.roboto
              pkgs.inter-nerdfont
            ];
          };
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "noctalia-shell";
            version = self.rev or self.dirtyRev or "dirty";
            src = ./.;

            nativeBuildInputs = [
              pkgs.gcc
              pkgs.makeWrapper
              pkgs.qt6.wrapQtAppsHook
            ];
            buildInputs = [
              qs
              pkgs.xkeyboard_config
              pkgs.qt6.qtbase
            ];
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
        }
      );

      defaultPackage = eachSystem (system: self.packages.${system}.default);

      homeModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.noctalia-shell;
        in
        {
          options.programs.noctalia-shell = {
            enable = lib.mkEnableOption "Noctalia shell configuration";

            settings = lib.mkOption {
              type =
                with lib.types;
                nullOr (oneOf [
                  attrs
                  str
                  path
                ]);
              default = null;
              example = lib.literalExpression ''
                {
                  bar = {
                    position = "bottom";
                    floating = true;
                    backgroundOpacity = 0.95;
                  };
                  general = {
                    animationSpeed = 1.5;
                    radiusRatio = 1.2;
                  };
                  colorSchemes = {
                    darkMode = true;
                    useWallpaperColors = true;
                  };
                }
              '';
              description = ''
                Noctalia shell configuration settings as an attribute set, string
                or filepath, to be written to ~/.config/noctalia/settings.json.
              '';
            };

            colors = lib.mkOption {
              type =
                with lib.types;
                nullOr (oneOf [
                  attrs
                  str
                  path
                ]);
              default = null;
              example = lib.literalExpression ''
                 {
                   mError = "#dddddd";
                   mOnError = "#111111";
                   mOnPrimary = "#111111";
                   mOnSecondary = "#111111";
                   mOnSurface = "#828282";
                   mOnSurfaceVariant = "#5d5d5d";
                   mOnTertiary = "#111111";
                   mOutline = "#3c3c3c";
                   mPrimary = "#aaaaaa";
                   mSecondary = "#a7a7a7";
                   mShadow = "#000000";
                   mSurface = "#111111";
                   mSurfaceVariant = "#191919";
                   mTertiary = "#cccccc";
                }
              '';
              description = ''
                Noctalia shell color configuration as an attribute set, string
                or filepath, to be written to ~/.config/noctalia/colors.json.
              '';
            };
          };

          config =
            let
              restart = ''
                ${pkgs.systemd}/bin/systemctl --user try-restart noctalia-shell.service 2>/dev/null || true
              '';
            in
            lib.mkIf cfg.enable {
              xdg.configFile = {
                "noctalia/settings.json" = lib.mkIf (cfg.settings != null) (
                  {
                    onChange = restart;
                  }
                  // (
                    if builtins.isAttrs cfg.settings then
                      { text = builtins.toJSON cfg.settings; }
                    else if builtins.isString cfg.settings then
                      { text = cfg.settings; }
                    else
                      { source = cfg.settings; }
                  )
                );
                "noctalia/colors.json" = lib.mkIf (cfg.colors != null) (
                  {
                    onChange = restart;
                  }
                  // (
                    if builtins.isAttrs cfg.colors then
                      { text = builtins.toJSON cfg.colors; }
                    else if builtins.isString cfg.colors then
                      { text = cfg.colors; }
                    else
                      { source = cfg.colors; }
                  )
                );
              };
            };
        };

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.noctalia-shell;
        in
        {
          options.services.noctalia-shell = {
            enable = lib.mkEnableOption "Noctalia shell systemd service";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The noctalia-shell package to use";
            };

            target = lib.mkOption {
              type = lib.types.str;
              default = "graphical-session.target";
              example = "hyprland-session.target";
              description = "The systemd target for the noctalia-shell service.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.user.services.noctalia-shell = {
              description = "Noctalia Shell - Wayland desktop shell";
              documentation = [ "https://github.com/noctalia-dev/noctalia-shell" ];
              after = [ cfg.target ];
              partOf = [ cfg.target ];
              wantedBy = [ cfg.target ];

              unitConfig = {
                StartLimitIntervalSec = 60;
                StartLimitBurst = 3;
              };

              serviceConfig = {
                ExecStart = "${cfg.package}/bin/noctalia-shell";
                Restart = "on-failure";
                RestartSec = 3;
                TimeoutStartSec = 10;
                TimeoutStopSec = 5;
                Environment = [ "PATH=${config.system.path}/bin" ];
              };
            };

            environment.systemPackages = [ cfg.package ];
          };
        };
    };
}
