{
  config,
  lib,
  ...
}:
let
  cfg = config.services.atmosphera;
in
{
  options.services.atmosphera = {
    enable = lib.mkEnableOption "Atmosphera systemd service";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The atmosphera package to use";
    };

    target = lib.mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      example = "hyprland-session.target";
      description = "The systemd target for the atmosphera service.";
    };

    bindings = {
      environment = lib.mkOption {
        type = lib.types.enum [ "none" "macos" ];
        default = "none";
        description = ''
          Which keyboard shortcut environment to bootstrap at the system level.
          When set to "macos", enables NixOS's services.keyd with the
          appropriate Alt<->Super hardware modifier swap. Users still opt in
          per-user via the setup wizard for the non-root layers (niri, xremap,
          zed).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = [
      ''
        Running atmosphera as a systemd service has been deprecated!
        Use the graphical session target instead.
      ''
    ];
    systemd.user.services.atmosphera = {
      description = "Atmosphera - Wayland desktop shell";
      documentation = [ "https://github.com/alexindigo/atmosphera" ];
      after = [ cfg.target ];
      partOf = [ cfg.target ];
      wantedBy = [ cfg.target ];
      restartTriggers = [ cfg.package ];

      environment = {
        PATH = lib.mkForce null;
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
      };
    };

    environment.systemPackages = [ cfg.package ];

    services.keyd = lib.mkIf (cfg.bindings.environment == "macos") {
      enable = true;
      keyboards.atmosphera = {
        ids = [ "*" ];
        settings = {
          main = {
            leftalt = "leftmeta";
            leftmeta = "leftalt";
            rightalt = "rightmeta";
            rightmeta = "rightalt";
          };
        };
      };
    };
  };
}
