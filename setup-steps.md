# SWG Infinity Mac Setup — Step by Step

Exact steps we followed to get the game running via Sikarugir on macOS (Apple Silicon).

---

## 1. Install Sikarugir

```bash
brew install --cask Sikarugir-App/sikarugir/sikarugir
softwareupdate --install-rosetta --agree-to-license
```

## 2. Create the wrapper

1. Open **Sikarugir Creator.app**
2. Click **Download Template** (downloads the Wine engine)
3. Select engine **WS12WineSikarugir10.0_6** from the dropdown
4. Click **Create**, name it **SWG Infinity**, save to Applications
5. Wait for prefix creation to finish — Creator may show "not responding" during this step (known issue, GitHub #142). It takes 5–15 minutes.
6. When the popup appears, select **Launch It** → Configure app opens

**Important:** If you previously had CrossOver or another Wine wrapper installed, kill any stale `wineserver` processes first — they block Sikarugir's prefix creation:

```bash
ps aux | grep wineserver | grep -v grep
kill -9 <PID>
```

## 3. Enable DXMT (optional)

In the Configure app, you can check **DirectX to Metal translation layer – (DXMT)**, but note it has no effect on SWG itself—DXMT doesn't support 32-bit x86, and the game renders via Wine's builtin d3d9 (WineD3D→OpenGL). Harmless either way.

## 4. Install DirectX 9 via Winetricks

1. In Configure, click **Winetricks**
2. Search for `d3dx9`
3. Check the top result: `d3dx9 — MS d3dx9_??.dll from DirectX 9 redistributable`
4. Click **Run**
5. Close Winetricks when done

## 5. Install the CLI

```bash
cd swg-infinity    # wherever you cloned this repo
make install       # symlinks bin/swg → ~/bin/swg
```

## 6. Get the game files

The Infinity launcher crashes under Wine (Tauri/WebView2 COM fault). The CLI downloads directly from the public patch server.

```bash
swg download
```

This fetches the manifest from `https://updater.swginfinity.com/manifest.json`, downloads all 51 files (~5.6 GB), and verifies MD5 hashes. Resumable — rerun to retry any failures.

## 7. Copy game files into the wrapper

```bash
WRAPPER="$HOME/Applications/Sikarugir/SWG Infinity.app/Contents/SharedSupport/prefix/drive_c"
mkdir -p "$WRAPPER/SWG Infinity"
cp -R ./game-files/* "$WRAPPER/SWG Infinity/"   # from the repo root
```

## 8. Authenticate

```bash
swg login --save
```

First run: authenticates via MFA (code arrives by email) and stores credentials in the macOS Keychain. Every run after that is zero-prompt—a stored refresh token skips MFA. Writes `swgemu_login.cfg` (server `game.swginfinity.com:14453`) + `swgemu.cfg` into the game directory, and patches `swgemu_live.cfg` with base `.tre` entries (`bottom.tre`, `infinity_xmas.tre`) if missing—these must be in the same `[SharedFile]` section as the patch entries, not in a separate config file.

## 9. Launch

The game must run with its working directory set to the game folder — Sikarugir's `start.exe` doesn't do this:

```bash
swg launch
```

This runs Wine directly with the correct CWD. Use `swg launch --login` to authenticate and launch in one step.

`swg launch` also replicates two things the Windows launcher does that the game cannot start without: it passes the launcher's command-line config args (`-s Station gameFeatures=65535 ...`—the client won't load its `.tre` archives otherwise) and caps the client's startup memory preallocation via `SWGCLIENT_MEMORY_SIZE_MB=1024` so it fits Wine's 32-bit address space (override: `SWG_MEMORY_MB=1536 swg launch`).

### First launch tips

- Enable **Windowed** + **Borderless** for best macOS experience
- Start with moderate graphics settings and increase
- If prompted about anticheat (Sentinel), it's DLL injection — Wine handles it fine

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Creator hangs during wrapper creation | Kill stale `wineserver` processes, restart Creator |
| "No new executables found" after DirectX install | Expected — use Winetricks `d3dx9` instead of the redistributable |
| `defaultappearance.apt could not be found` / `int3` crash | Game launched without the launcher's command-line args — the client won't load `.tre` archives without them. Use `swg launch` (passes them automatically). |
| `allocate_virtual_memory out of memory` | Client preallocates ~2.6 GB, too big for Wine's 32-bit address space. `swg launch` caps it at 1024 MB via `SWGCLIENT_MEMORY_SIZE_MB`; adjust with `SWG_MEMORY_MB`. |
| `Login Server is currently not available` | Wrong login address — Infinity uses port **14453**, not SWGEmu's 44453. `swg login` writes the right one; `swg server <host:port>` pins an override. |
| Black screen, game exits in ~20s | Game resolution larger than the scaled macOS desktop → fullscreen fallback to a nonexistent mode. `swg options resolution 1728x1080` (or whatever fits). |
| `libinotify.0.dylib` not loaded | Use `swg launch` (sets `DYLD_FALLBACK_LIBRARY_PATH`) instead of double-clicking the wrapper |
| Game crashes immediately after MoltenVK init | CWD wrong — use `swg launch`, not Sikarugir's built-in launch |
| Weird FPS / VSync issues | Run in windowed/borderless mode |
| Anticheat warning | Sentinel is DLL-based, not kernel — Wine-compatible |
