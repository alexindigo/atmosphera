{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.noctalia-shell;
  jsonFormat = pkgs.formats.json { };
  tomlFormat = pkgs.formats.toml { };

  generateJson =
    name: value:
    if lib.isString value then
      pkgs.writeText "noctalia-${name}.json" value
    else if builtins.isPath value || lib.isStorePath value then
      value
    else
      jsonFormat.generate "noctalia-${name}.json" value;
in
{
  options.programs.noctalia-shell = {
    enable = lib.mkEnableOption "Noctalia shell configuration";

    systemd.enable = lib.mkEnableOption "Noctalia shell systemd integration";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      description = "The noctalia-shell package to use";
    };

    settings = lib.mkOption {
      type =
        with lib.types;
        oneOf [
          jsonFormat.type
          str
          path
        ];
      default = { };
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
        oneOf [
          jsonFormat.type
          str
          path
        ];
      default = { };
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

    user-templates = lib.mkOption {
      type = lib.types.submodule {
        options = {
          config = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
            description = "General [config] section for Matugen’s TOML config file.";
          };
          templates = lib.mkOption {
            default = { };
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  inputPath = lib.mkOption {
                    type = lib.types.path;
                    description = "Template input path for Matugen";
                  };
                  outputPath = lib.mkOption {
                    type = lib.types.path;
                    description = "Output path where the generated file will be written";
                  };
                  postHook = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Command to run after file is generated";
                  };
                };
              }
            );
          };
        };
      };
      default = { };
      example = lib.literalExpression ''
        programs.noctalia-shell.user-templates = {
          templates = {
            neovim = {
              inputPath = "~/.config/matugen/templates/template.lua";
              outputPath = "~/.config/nvim/generated.lua";
              postHook = "pkill -SIGUSR1 nvim";
            };
          };
        };
      '';
      description = ''
        Template definitions for Matugen. Each attribute corresponds to a template
        such as "neovim", "kitty", "btop".
      '';
    };

    app2unit.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.app2unit;
      description = ''
        The app2unit package to use when appLauncher.useApp2Unit is enabled.
      '';
    };
  };

  config =
    let
      restart = "${pkgs.systemd}/bin/systemctl --user try-restart noctalia-shell.service 2>/dev/null || true";
      useApp2Unit = cfg.settings.appLauncher.useApp2Unit or false;
    in
    lib.mkIf cfg.enable {
      systemd.user.services.noctalia-shell = lib.mkIf cfg.systemd.enable {
        Unit = {
          Description = "Noctalia Shell - Wayland desktop shell";
          Documentation = "https://docs.noctalia.dev/docs";
          PartOf = [ config.wayland.systemd.target ];
          After = [ config.wayland.systemd.target ];
          X-Restart-Triggers =
            lib.optional (cfg.settings != { }) config.xdg.configFile."noctalia/settings.json".source
            ++ lib.optional (cfg.colors != { }) config.xdg.configFile."noctalia/colors.json".source;
        };

        Service = {
          ExecStart = lib.getExe cfg.package;
          Restart = "on-failure";
          Environment = [
            "NOCTALIA_SETTINGS_FALLBACK=%h/.config/noctalia/gui-settings.json"
          ];
        };

        Install.WantedBy = [ config.wayland.systemd.target ];
      };

      home.packages =
        lib.optional useApp2Unit cfg.app2unit.package ++ lib.optional (cfg.package != null) cfg.package;

      xdg.configFile = {
        "noctalia/settings.json" = lib.mkIf (cfg.settings != { }) {
          onChange = lib.mkIf (!cfg.systemd.enable) restart;
          source = generateJson "settings" cfg.settings;
        };
        "noctalia/colors.json" = lib.mkIf (cfg.colors != { }) {
          onChange = lib.mkIf (!cfg.systemd.enable) restart;
          source = generateJson "colors" cfg.colors;
        };
        "noctalia/user-templates.toml" = {
          onChange = lib.mkIf (!cfg.systemd.enable) restart;
          source = tomlFormat.generate "user-templates.toml" {
            config = cfg.user-templates.config;
            templates = lib.mapAttrs (_: t: {
              input_path = t.inputPath;
              output_path = t.outputPath;
              post_hook = t.postHook;
            }) cfg.user-templates.templates;
          };
        };

      };

      assertions = [
        {
          assertion = !cfg.systemd.enable || cfg.package != null;
          message = "noctalia-shell: The package option must not be null when systemd service is enabled.";
        }
      ];
    };
}
