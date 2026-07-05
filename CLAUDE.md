# SWG Infinity on Mac

## What This Is

Mac setup guide + CLI tooling for [SWG Infinity](https://www.swginfinity.com/), a pre-CU Star Wars Galaxies private server. The Tauri-based Windows launcher crashes under Wine (WebView2 COM fault in ole32.dll), so the `swg` CLI bypasses it entirely—downloading game files from the public patch server, authenticating via the API, and launching the game client through Sikarugir (free Wine wrapper with DXMT).

## Architecture

```
swg-infinity/
├── bin/swg                     # CLI entry point — sources lib/*.sh, dispatches subcommands
├── lib/
│   ├── swg-core.sh             # Shared constants (WRAPPER, WINE, PREFIX), logging, plist helpers
│   ├── swg-wine.sh             # Wine env setup, exe invocation, crash diagnostics
│   ├── swg-audit.sh            # Config file + TRE file validation
│   ├── swg-auth.sh             # Auth flow (MFA), config writing, live.cfg patching
│   ├── swg-download.sh         # Manifest fetch, file download, MD5 verify
│   └── swg-manage.sh           # Status, config, options, autologin, server pin, winetricks
├── completions/swg.zsh         # Zsh tab completions
├── Makefile                    # install/uninstall (symlink bin/swg → ~/bin/swg)
├── launch.sh                   # Shim → exec bin/swg launch
├── login.sh                    # Shim → exec bin/swg login
├── download-game.sh            # Shim → exec bin/swg download
├── README.md                   # Full Mac setup guide
├── setup-steps.md              # Condensed step-by-step (commands only)
├── infrastructure.md           # Launcher internals, server infra, auth flow
└── demos/project-thorn/        # Interactive Imperial Intelligence terminal demo
```

## CLI

`swg <command> [options]` — all game management from one tool.

| Command | Description |
|---------|-------------|
| `launch [--login]` | Diagnostic audit + Wine launch (memory cap, launcher args, session auto-login) |
| `login [--save\|--forget]` | Authenticate (Keychain + refresh token skip MFA), write configs, patch `.tre` entries |
| `download [--target dir]` | Download game files from patch server (~5.6 GB, MD5-verified) |
| `audit` | Validate config + TRE files + display snapshot, exit 0/1 |
| `status` | Wine version, renderer, file counts, server reachability |
| `config [key [value]]` | Read/write Sikarugir plist flags |
| `options [key [value]]` | Read/write game display settings in options.cfg |
| `autologin [on\|off]` | Toggle in-game login-screen skip |
| `server [host:port]` | Pin login server over discovery |
| `winetricks <verb>` | Install components via wrapper's winetricks |
| `shell` | Subshell with Wine env vars set |
| `kill` | Kill the wineserver |

**Env knobs:** `SWG_MEMORY_MB` (client memory cap, default 1024), `SWG_AUTOLOGIN=0/1`, `SWG_LOGIN_HOST/PORT`, `SWG_DEBUG_API=1` (log API response key names), `SWG_DEBUG_DISPLAY=1` (trace display-mode matching). Persistent settings live in `~/.config/swg/config`; env vars win.

**Library structure:** `swg-core.sh` defines shared constants (`WRAPPER`, `WINE`, `PREFIX`, `GAME_DIR`, `PLIST`) and helpers (`swg_log`, `swg_die`, `swg_require`, `swg_plist_read/write`). All other libs depend on it. Each subcommand maps to a `swg_cmd_*` function in its lib file.

**Dependencies:** `bash`, `curl`, `python3` (stdlib only)

## Key Infrastructure

- **Patch server**: `https://updater.swginfinity.com`
- **Game manifest**: `https://updater.swginfinity.com/manifest.json` — 51 files, MD5-verified
- **File hosting**: Dropbox via 302 redirect from `https://updater.swginfinity.com/files/live/{filename}`
- **Auth API**: `https://my.swginfinity.com/api/auth` — login, MFA email-code, verify, refresh (verify/refresh responses carry `sessionId`)
- **Launcher API**: `https://api2.swginfinity.com/api/v2` — note `api2`, not `api`; `POST /game/session` returns `{host, port, sessionId, serverEnv}`
- **Login server**: `game.swginfinity.com:14453` (LIVE) — custom port, NOT SWGEmu's default 44453; Test Center is `tc.swginfinity.com:24453`

## The Launcher Problem

The Infinity Launcher (Tauri/Rust + WebView2) crashes under Wine—page fault in ole32.dll during COM initialization. The game client (`SwgClient_r.exe`) runs fine. The launcher is just a download/patch manager—the CLI replaces it completely.

## Sikarugir

- **Wrapper**: `~/Applications/Sikarugir/SWG Infinity.app`
- **Wine prefix**: `Contents/SharedSupport/prefix/`
- **Game dir**: `prefix/drive_c/SWG Infinity/`
- **Config parser quirk**: duplicate `[SharedFile]` sections replace rather than merge—all `.tre` entries must live in one section (`swg login` handles this)
- **Launch requirements**: the client won't load `.tre` archives without the launcher's command-line config args, and its ~2.6 GB startup preallocation must be capped via `SWGCLIENT_MEMORY_SIZE_MB` to fit wow64's 32-bit address space—`swg launch` handles both (see `infrastructure.md` § What the Launcher Provides at Launch)
- **DXMT is inert for SWG**: no 32-bit x86 support; the game renders via Wine's builtin d3d9 (WineD3D→OpenGL)

## Project Thorn

Interactive Imperial Intelligence terminal demo in `demos/project-thorn/`. Built from 2003-era SWG character bios (Vorian Ducal / Jiff Gorda). Single HTML file, no dependencies. See `demos/project-thorn/README.md`.

## Conventions

- README voice: connected em dashes (—), no hedging, declarative prose
- No Co-Authored-By trailers in commits
- Screenshots: descriptive kebab-case filenames
- Shell: `set -euo pipefail`, function names prefixed `swg_`, subcommand handlers prefixed `swg_cmd_`
