# Plan: SWG Infinity Unified CLI

## Context

SWG Infinity runs on macOS via Sikarugir (a free Wine wrapper). Three standalone shell scripts manage the game: `launch.sh` (229 lines — diagnostics, config audit, TRE audit, Wine launch), `login.sh` (199 lines — auth flow, config writing), and `download-game.sh` (102 lines — manifest fetch, file download). Each script hardcodes the wrapper path, duplicates Wine env setup, and has no shared infrastructure. A unified `swg` CLI consolidates these into subcommands with shared library functions.

## Decisions

- **Language**: Bash (matches existing scripts, zero deps)
- **CLI name**: `swg`
- **Repo**: `swg-infinity/` on `main`, no branches
- **Install**: `make install` symlinks `bin/swg` to `~/bin/swg`
- **Backward compat**: Existing `launch.sh`, `login.sh`, `download-game.sh` become one-line shims that `exec bin/swg <subcommand> "$@"`

---

## Directory Structure

```
swg-infinity/
├── bin/
│   └── swg                 # Entry point — sources lib/*.sh, dispatches subcommands
├── lib/
│   ├── swg-core.sh         # Wrapper path resolution, logging, shared constants
│   ├── swg-wine.sh         # Wine env setup, direct invocation, crash diagnostics
│   ├── swg-audit.sh        # Config file + TRE file validation
│   ├── swg-auth.sh         # Auth flow (MFA, config writing, live.cfg patching)
│   └── swg-download.sh     # Manifest fetch, file download, MD5 verify
├── completions/
│   └── swg.zsh             # Zsh completions
├── Makefile                # install/uninstall (symlink bin/swg → ~/bin/swg)
├── launch.sh               # SHIM → exec bin/swg launch "$@"
├── login.sh                # SHIM → exec bin/swg login "$@"
├── download-game.sh        # SHIM → exec bin/swg download "$@"
├── README.md
├── CLAUDE.md
└── ...existing files...
```

## Subcommands

| Command | Replaces | Description |
|---------|----------|-------------|
| `swg launch [--login]` | `launch.sh` | Full diagnostic audit + Wine launch. `--login` runs auth first. |
| `swg login` | `login.sh` | Authenticate with MFA, write swgemu_login.cfg + swgemu.cfg, patch swgemu_live.cfg |
| `swg download [--target dir]` | `download-game.sh` | Download game files from patch server manifest |
| `swg audit` | (new) | Run config + TRE audit without launching — exits 0 if clean, 1 if problems |
| `swg status` | (new) | Show wrapper state: Wine version, renderer, file counts, server reachability |
| `swg config [key [value]]` | (new) | Read/write Sikarugir plist flags (DXMT, WINEESYNC, Debug Mode, etc.) |
| `swg winetricks <verb>` | (new) | Install winetricks components into the wrapper |
| `swg shell` | (new) | Open subshell with WINEPREFIX and Wine env vars set |
| `swg kill` | (new) | Kill the wineserver |

## Critical Files

### `bin/swg` (~60 lines)
Resolves its own location, sources all `lib/swg-*.sh` files, parses the subcommand from `$1`, dispatches to the matching function. Prints usage on unknown subcommand.

### `lib/swg-core.sh` (~40 lines)
Shared constants and helpers:
- `WRAPPER`, `WINE`, `PREFIX`, `GAME_DIR`, `PLIST` — derived from `~/Applications/Sikarugir/SWG Infinity.app`
- `swg_log()` — timestamped logging to stdout + optional log file
- `swg_die()` — log + exit 1
- `swg_require()` — assert file/dir exists or die

### `lib/swg-wine.sh` (~80 lines)
Extracted from `launch.sh:175-229`:
- `swg_setup_wine_env()` — exports `WINEPREFIX`, `WINEESYNC`, `WINEMSYNC`, `DYLD_FALLBACK_LIBRARY_PATH`
- `swg_run_wine()` — `cd "$GAME_DIR" && "$WINE" "$@"` with exit code capture, crash dump detection, timing
- `swg_kill_wineserver()` — `"$WINE"server -k`
- `swg_open_shell()` — `exec $SHELL` with env vars set
- `swg_show_status()` — Wine version, active renderer, plist flags, file counts, `curl -s` server ping

### `lib/swg-audit.sh` (~100 lines)
Extracted from `launch.sh:58-149`:
- `swg_audit_configs()` — check required/optional config files exist, validate content (loginServerAddress, searchTree, .include targets)
- `swg_audit_tres()` — count .tre files, cross-reference config entries against disk, case-sensitivity check
- `swg_audit_system()` — macOS version, chip, RAM, GPU, Wine version
- `swg_audit_plist()` — read and display renderer/sync/debug flags from Info.plist
- `swg_audit_all()` — run all audits, return exit code based on whether any FATAL issues found

### `lib/swg-auth.sh` (~120 lines)
Extracted from `login.sh`:
- `swg_login()` — interactive username/password prompt, POST to auth API, MFA flow, server config discovery
- `swg_write_login_cfg()` — write `swgemu_login.cfg`
- `swg_write_swgemu_cfg()` — write master `swgemu.cfg` (without preload include)
- `swg_patch_live_cfg()` — add `bottom.tre` + `infinity_xmas.tre` to `swgemu_live.cfg` if missing

### `lib/swg-download.sh` (~80 lines)
Extracted from `download-game.sh`:
- `swg_download()` — fetch manifest, download files with MD5 verify, skip existing

### Shim updates (~3 lines each)
Each existing script becomes:
```bash
#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/bin/swg" launch "$@"
```

---

## Implementation Order

1. **`lib/swg-core.sh`** — shared constants, logging helpers
2. **`bin/swg`** — entry point skeleton with usage and dispatch
3. **`lib/swg-wine.sh`** + `launch` subcommand (extract from `launch.sh`)
4. **`lib/swg-audit.sh`** + `audit` subcommand (extract from `launch.sh`)
5. **`lib/swg-auth.sh`** + `login` subcommand (extract from `login.sh`)
6. **`lib/swg-download.sh`** + `download` subcommand (extract from `download-game.sh`)
7. **`status`, `config`, `winetricks`, `shell`, `kill`** subcommands (new functionality)
8. **Shim the original scripts** — replace bodies with `exec bin/swg`
9. **`completions/swg.zsh`** + **`Makefile`**

Steps 1-6 are pure refactor — no new behavior, just reorganization. Step 7 adds new capabilities. Step 8 is backward compat. Step 9 is polish.

## Verification

```bash
# Core functionality (must match existing behavior exactly)
swg launch --login               # same as: ./launch.sh --login
swg login                        # same as: ./login.sh
swg download --target ./files    # same as: ./download-game.sh

# Backward compat (shims)
./launch.sh                      # delegates to swg launch
./login.sh                       # delegates to swg login
./download-game.sh               # delegates to swg download

# New subcommands
swg audit                        # config + TRE audit, exit 0/1
swg status                       # wrapper state summary
swg config DXMT                  # read plist flag → "1"
swg config METAL_HUD 1           # write plist flag
swg winetricks vcrun2019         # install via wrapper's winetricks
swg shell                        # subshell with Wine env
swg kill                         # stop wineserver
```

## Scope Boundaries

- **SWG Infinity only.** Not a general Sikarugir tool.
- **No wrapper creation.** That's Sikarugir Creator's job.
- **No GUI.** CLI only.
- **Existing behavior preserved.** The refactor must not change what `launch.sh`, `login.sh`, and `download-game.sh` currently do — just reorganize it.
