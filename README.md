# autonym

## interactive alias generator for [nushell](https://www.nushell.sh)

autonym finds the commands you run frequently, then proposes 2-5 letter aliases for them.
enable the ones you like, and nushell will automatically pull them in at next startup.

## install

with the nixos module, open a new shell after rebuilding and run:

```nu
autonym generate
```

without the nixos module, make the module available to nushell and import it:

```nu
use autonym
```

enabled aliases are written to nushell's user autoload directory and load in new shells.

## enabling aliases

suggestions are inert until you approve them. rejected suggestions are never
offered again. rerunning `autonym generate` persists enable/reject state.

how to enable:
- `autonym` opens a review list: arrows or jk move, space cycles approval state
  y and x confirm and reject, enter saves
- `autonym enable <name>` and `autonym reject <name>` for one at a time
- edit the aliases file directly and uncomment a line

## commands

| command | does |
|---------|------|
| `autonym` | review current suggestions |
| `autonym scan` | preview the ranked suggestions without writing anything |
| `autonym generate` | write the aliases file |
| `autonym status` | enabled / rejected / pending counts |
| `autonym enable <name>` | turn a suggestion on |
| `autonym reject <name>` | dismiss a suggestion for good |

`scan` and `generate` take:
- `--min-count`: minimum number of appearances
- `--min-savings`: minimum number of characters saved by the alias
- `--top`: only display top n results
- `--history`: point to custom shell history path
- `--limit`: limit scan to n shell history lines

by default, the most recent 1000 entries are scanned (you may also set
`AUTONYM_HISTORY_LIMIT`)

## prompt notices

nixos enables prompt notices by default. to turn them off:

```nix
programs.autonym.enableHook = false;
```

to tune announcement frequency:

```nix
programs.autonym.hookEveryMin = 300;
programs.autonym.hookMinPrompts = 50;
```

without the nixos module, append the hook to `config.nu`:

```nu
autonym hook snippet | save --append $nu.config-path
```

when new suggestions exist, you will get a single line above the prompt:

```
[!] 5 new shortcuts to review; check autonym
```

this will only show after both the time and prompt-count thresholds have passed.


## nixos

```nix
{
  imports = [ inputs.autonym.nixosModules.default ];
  programs.autonym.enable = true;
}
```

this installs the `autonym` nushell module through Nu's vendor autoload
directory. the prompt notice hook is enabled by default.

- `programs.autonym.historyLimit` sets how many recent entries to scan
- `programs.autonym.enableHook = false` skips prompt notices
- `programs.autonym.hookEveryMin` and `programs.autonym.hookMinPrompts` tune prompt notice frequency
