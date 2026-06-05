{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.autonym;

  autonym = pkgs.runCommandLocal "autonym" { } ''
    mkdir -p $out/share/nushell/vendor/autonym
    cp -r ${./autonym}/* $out/share/nushell/vendor/autonym/

    mkdir -p $out/share/nushell/vendor/autoload
    cat > $out/share/nushell/vendor/autoload/autonym.nu <<'EOF'
    use ../autonym
    ${lib.optionalString cfg.enableHook ''
      $env.AUTONYM_EVERY_MIN = ${toString cfg.hookEveryMin}
      $env.AUTONYM_MIN_PROMPTS = ${toString cfg.hookMinPrompts}
      $env.AUTONYM_TICK = 0
      $env.AUTONYM_LAST = (date now)
      $env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt? | default [] | append {
        code: "$env.AUTONYM_TICK = ($env.AUTONYM_TICK + 1); if ((((date now) - $env.AUTONYM_LAST) >= ($env.AUTONYM_EVERY_MIN * 1min)) and ($env.AUTONYM_TICK >= $env.AUTONYM_MIN_PROMPTS)) { $env.AUTONYM_TICK = 0; $env.AUTONYM_LAST = (date now); autonym hook tick }"
      })
    ''}
    EOF
  '';
in
{
  options.programs.autonym = {
    enable = lib.mkEnableOption "autonym nushell acronym generator";

    package = lib.mkOption {
      type = lib.types.package;
      default = autonym;
      description = "the autonym nushell module bundle.";
    };

    historyLimit = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "scan only the most recent N history entries (0 for all).";
    };

    enableHook = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "whether to install autonym's nushell pre-prompt notification hook.";
    };

    hookEveryMin = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "minimum minutes between autonym prompt notices.";
    };

    hookMinPrompts = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "minimum prompts between autonym prompt notices.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.extraSetup = ''
      mkdir -p $out/share/nushell/vendor/autoload
      if [ ! -e $out/share/nushell/vendor/autonym ]; then
        ln -s ${cfg.package}/share/nushell/vendor/autonym $out/share/nushell/vendor/autonym
      fi
      if [ ! -e $out/share/nushell/vendor/autoload/autonym.nu ]; then
        ln -s ${cfg.package}/share/nushell/vendor/autoload/autonym.nu $out/share/nushell/vendor/autoload/autonym.nu
      fi
    '';
    environment.variables.AUTONYM_HISTORY_LIMIT = toString cfg.historyLimit;
  };
}
