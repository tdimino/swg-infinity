# SWG Infinity Infrastructure

Technical reference for the Infinity launcher's internals, server infrastructure, and authentication flow. All findings from reverse-engineering the launcher binary and probing public endpoints.

---

## Launcher Architecture

The Infinity Launcher (v0.2.22) is a **Tauri/Rust** app with a WebView2 frontend.

- **Binary**: `infinity-launcher.exe` (32 MB, built by `C:\Users\JD\`)
- **Anticheat**: `sentinel-injector.exe` + `sentinel_anticheat.dll` (DLL injection, not kernel-level)
- **Installer**: NSIS wrapper (`Infinity-Launcher-Setup.exe`, 15 MB)

### Config file chain

The game client loads configs via `.include` directives in `swgemu.cfg`:

```
.include "options.cfg"
.include "swgemu_live.cfg"
.include "swgemu_login.cfg"
.include "user_autologin.cfg"   (CLI addition — session auto-login, absent unless launching)
.include "user_infinity.cfg"
.include "user.cfg"
```

**Critical**: the SWG config parser **replaces** duplicate INI sections instead of merging them. If two included files both define `[SharedFile]`, the second one overwrites the first entirely. This is why `swgemu_preload.cfg` (which the Windows launcher generates with its own `[SharedFile]` header) must NOT be included separately—its entries must go directly into `swgemu_live.cfg`. Our `swg login` handles this automatically.

### Launcher Tauri commands

Key IPC commands exposed by the Rust backend:

| Command | Parameters | Purpose |
|---------|-----------|---------|
| `launch_game` | `safeMode`, `loginHost`, `loginPort`, `sessionId`, `loginUsername`, `adminLevel`, `serverEnv` | Start the game client |
| `save_auth_tokens` | `accessToken`, `refreshToken`, `expiresAt` | Store auth credentials |
| `test_game_connection` | `host`, `port` | Verify server reachability |
| `write_options_cfg` | — | Generate options.cfg |
| `inject_anticheat` | — | Load Sentinel DLLs |
| `patch_swgemu_fps` | `fps` | Set FPS cap |
| `install_dxvk` / `remove_dxvk` | — | Toggle DXVK |
| `write_qol_ini` / `read_qol_ini` | — | QoL mod settings |

### What the launcher does at game launch

1. Authenticates user via web API → gets `accessToken`, `refreshToken`
2. Receives `loginHost`, `loginPort`, `sessionId` from the authenticated API
3. Writes `swgemu_login.cfg` with `loginServerAddress0` and `loginServerPort0`
4. Optionally injects Sentinel anticheat DLLs
5. Launches `swgemu.exe` with the config chain

---

## Server Infrastructure

### DNS

| Hostname | IP | Purpose |
|----------|-----|---------|
| `swginfinity.com` | 104.21.73.95 / 172.67.189.90 | Website (Cloudflare) |
| `api.swginfinity.com` | 104.21.73.95 / 172.67.189.90 | Backend API (Cloudflare) |
| `api2.swginfinity.com` | — | Launcher API (the one the launcher actually calls) |
| `game.swginfinity.com` | 148.113.160.16 (OVH, direct) | LIVE login server — port **14453** |
| `tc.swginfinity.com` | — | Test Center login server — port 24453 |
| `live.swginfinity.com` | 51.222.153.102 (OVH, direct) | Unreferenced by the launcher |

### API endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `https://updater.swginfinity.com/manifest.json` | GET | No | Game file manifest (51 files, ~5.6 GB) |
| `https://updater.swginfinity.com/files/live/{filename}` | GET | No | File download (302 → Dropbox) |
| `https://updater.swginfinity.com/api/v2/launcher/update-check` | GET | No | Launcher version check |
| `https://my.swginfinity.com/api/auth/login` | POST | No | Login (username, password, mfaEnabled, sessionDurationDays) |
| `https://my.swginfinity.com/api/auth/email-code` | POST | MFA token | Request email MFA code |
| `https://my.swginfinity.com/api/auth/verify-email-code` | POST | MFA token + code | Verify MFA → `{accessToken, refreshToken, sessionId}` |
| `https://my.swginfinity.com/api/auth/refresh` | POST | `{refreshToken}` | Rotate tokens → `{accessToken, refreshToken, sessionId}` — no MFA |
| `https://api2.swginfinity.com/api/v2/launcher/config` | GET | Bearer token | Launcher configuration |
| `https://api2.swginfinity.com/api/v2/game/session` | POST | Bearer token, `{"server":"live"}` | Game session → `{host, port, sessionId, serverEnv}` |

Note: `api.swginfinity.com` (without the `2`) serves the website; the launcher's authenticated calls go to **`api2`** — recovered from the launcher's brotli-compressed frontend bundle (`/assets/index-*.js`), along with the hardcoded server table: `LIVE: game.swginfinity.com:14453`, `TC: tc.swginfinity.com:24453`.

### Authentication flow

```
1. POST /api/auth/login { username, password, mfaEnabled: true, sessionDurationDays }
   → Success: { accessToken, refreshToken, expiresAt }
   → MFA required: { mfaToken } (triggers email code)

2. POST /api/auth/email-code { mfaToken }
   → Sends verification code to user's email

3. POST /api/auth/verify-email-code { mfaToken, code }
   → { accessToken, refreshToken, expiresAt }

4. Launcher POSTs api2.swginfinity.com/api/v2/game/session {"server":"live"}
   → Receives {host, port, sessionId, serverEnv} for game launch

(Our CLI shortcut: the sessionId already arrives in the verify/refresh
responses, so swg login uses those directly.)
```

### Login server ports

| Server | Host | Port |
|--------|------|------|
| LIVE | `game.swginfinity.com` | **14453** (UDP) |
| Test Center | `tc.swginfinity.com` | 24453 (UDP) |

Infinity does **not** use the canonical SWGEmu login port (44453) — connecting there produces the client's "Login Server is currently not available" timeout. The real ports were recovered from the launcher frontend's hardcoded server table. `swg login` writes 14453 by default; `swg server <host:port>` pins an override.

---

## What the Launcher Provides at Launch

The Infinity launcher does more than download files and write configs — it launches the client with command-line arguments and environment variables the game cannot start without. All of the following were extracted from `infinity-launcher.exe` strings and confirmed by `WINEDEBUG=+file` tracing. `swg launch` replicates every item.

### Command-line config args (critical)

The client refuses to load its `.tre` archives unless launched with the launcher's config arguments:

```
swgemu.exe -- -s Station subscriptionFeatures=1 gameFeatures=65535 -s SwgClient allowMultipleInstances=true
```

Launched bare, the client reads every config file normally but TreeFile registers zero archives — a `WINEDEBUG=+file` trace shows the `.cfg` reads with not a single `.tre` open following them. The first asset lookup then dies: `FATAL 4d962776: appearance/defaultappearance.apt could not be found` (`int3` at `swgemu+0x6a1e3f`, the Fatal() handler). With the args, all 25 patch archives open and the game reaches the title screen.

The launcher also passes `-s ClientGame loginServerAddress0=<host> loginServerPort0=<port> sessionId=<id>` — the address/port are redundant with `swgemu_login.cfg` (which we write), and `sessionId` enables auto-login past the login screen. `swg launch --login` replicates this via a just-in-time `user_autologin.cfg` (chmod 600, deleted after the game exits) carrying `loginClientID`, `loginClientPassword`, and `sessionId` from the auth API. Toggle with `swg autologin on|off`.

### Client memory manager cap (critical under Wine)

The client's MemoryManager preallocates ~75% of reported RAM as one contiguous block at startup — Wine's wow64 reports ~3.5 GB, so the client attempts ~2.6 GB (`allocate_virtual_memory out of memory for allocation, size a8010000`). The 32-bit address space under wow64 on Apple Silicon is fragmented by dyld, Rosetta, and libSystem; the allocation fails intermittently and fatally.

The launcher sets the `SWGCLIENT_MEMORY_SIZE_MB` environment variable (checked in the client's `WinMain` before the default sizing formula — see SWG-Source `client-tools`: `WinMain.cpp`, `sharedMemoryManager/MemoryManager.cpp`). `swg launch` sets it to 1024; override via `SWG_MEMORY_MB`.

### Base `.tre` registration

The launcher registers `bottom.tre` and `infinity_xmas.tre` in the searchTree at priority 00 via a generated `swgemu_preload.cfg`. Our `swg login` patches these entries directly into `swgemu_live.cfg`'s `[SharedFile]` section instead.

### `swgemu_login.cfg` (critical)

Server connection details — written by the launcher after authentication. Our `swg login` replicates this.

```ini
[ClientGame]
loginServerAddress0=game.swginfinity.com
loginServerPort0=14453
autoConnectToLoginServer=true
```

### Working directory (critical)

SWG requires CWD = game directory because `.tre` paths in `swgemu_live.cfg` are relative. Sikarugir launches via `start.exe`, which doesn't propagate CWD. Confirmed by Lutris SWG Legends config, which explicitly sets `working_dir`. Our `swg launch` bypasses `start.exe` and runs Wine directly with `cd` into the game folder.

### Sentinel anticheat (optional)

The launcher injects `sentinel_anticheat.dll`. Linux players report mixed results without it — the game server may or may not enforce it.

---

## Files in this repo

| File | Purpose |
|------|---------|
| `infrastructure.md` | This file — launcher internals and server infrastructure |
| `setup-steps.md` | Condensed setup steps |
| `README.md` | Full Mac setup guide (see its Repo structure section for the full tree) |
| `bin/swg` + `lib/*.sh` | Unified CLI — download, login, audit, launch, manage |
| `download-game.sh`, `login.sh`, `launch.sh` | Backward-compat shims → `swg` subcommands |
| `Infinity-Launcher-Setup.exe` | Archived launcher installer (gitignored, local only) |
