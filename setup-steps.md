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

## 3. Enable DXMT

In the Configure app, check **DirectX to Metal translation layer – (DXMT)**. This is the biggest performance lever on Apple Silicon.

## 4. Install DirectX 9 via Winetricks

1. In Configure, click **Winetricks**
2. Search for `d3dx9`
3. Check the top result: `d3dx9 — MS d3dx9_??.dll from DirectX 9 redistributable`
4. Click **Run**
5. Close Winetricks when done

## 5. Get the game files

The Infinity launcher crashes under Wine (Tauri/WebView2 COM fault). We bypass it and download directly from the public patch server.

```bash
cd ~/Desktop/Programming/swg-infinity
./download-game.sh
```

This fetches the manifest from `https://updater.swginfinity.com/manifest.json`, downloads all 51 files (~5.6 GB), and verifies MD5 hashes. Resumable — rerun to retry any failures.

## 6. Copy game files into the wrapper

```bash
WRAPPER="$HOME/Applications/Sikarugir/SWG Infinity.app/Contents/SharedSupport/prefix/drive_c"
mkdir -p "$WRAPPER/SWG Infinity"
cp -R ~/Desktop/Programming/swg-infinity/game-files/* "$WRAPPER/SWG Infinity/"
```

## 7. Authenticate

```bash
cd ~/Desktop/Programming/swg-infinity
./login.sh
```

Authenticates via MFA and writes `swgemu_login.cfg` + `swgemu.cfg` into the game directory. Also patches `swgemu_live.cfg` with base `.tre` entries (`bottom.tre`, `infinity_xmas.tre`) if missing—these must be in the same `[SharedFile]` section as the patch entries, not in a separate config file.

## 8. Launch

The game must run with its working directory set to the game folder — Sikarugir's `start.exe` doesn't do this, so use the launch script:

```bash
./launch.sh
```

This runs Wine directly with the correct CWD. Use `./launch.sh --login` to authenticate and launch in one step.

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
| `defaultappearance.apt could not be found` / `int3` crash | Base `.tre` entries missing from `swgemu_live.cfg`, or in a separate `swgemu_preload.cfg` with its own `[SharedFile]` header (SWG's config parser replaces duplicate sections). Run `login.sh` to patch. |
| `libinotify.0.dylib` not loaded | Use `launch.sh` (sets `DYLD_FALLBACK_LIBRARY_PATH`) instead of double-clicking the wrapper |
| Game crashes immediately after MoltenVK init | CWD wrong — use `launch.sh`, not Sikarugir's built-in launch |
| Weird FPS / VSync issues | Run in windowed/borderless mode |
| Anticheat warning | Sentinel is DLL-based, not kernel — Wine-compatible |
