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
  };
}
