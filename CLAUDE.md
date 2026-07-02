# SWG Infinity on Mac

## What This Is

Mac setup guide + download tooling for [SWG Infinity](https://www.swginfinity.com/), a pre-CU Star Wars Galaxies private server. The Tauri-based Windows launcher crashes under Wine (WebView2 COM fault in ole32.dll), so we bypass it entirely—downloading game files directly from the public patch server and running the game client through Sikarugir (free Wine wrapper with DXMT).

## Architecture

```
swg-infinity/
├── README.md                    # Full Mac setup guide (Sikarugir + direct download)
├── setup-steps.md               # Condensed step-by-step setup (commands only)
├── infrastructure.md            # Launcher internals, server infra, auth flow
├── login.sh                     # Auth script — replicates launcher's login flow
├── launch.sh                   # Runs Wine directly with correct CWD + env vars
├── CLAUDE.md                    # This file
├── download-game.sh             # Downloads all game files from patch server
├── Infinity-Launcher-Setup.exe  # Windows launcher installer (archived reference)
├── project-thorn-intercept.png  # README screenshot
├── project-thorn-dossier.png    # README screenshot
└── demos/
    └── project-thorn/           # Interactive Imperial Intelligence terminal demo
```

## Key Infrastructure

- **Patch server**: `https://updater.swginfinity.com`
- **Game manifest**: `https://updater.swginfinity.com/manifest.json` — 51 files, ~5.6 GB, MD5-verified
- **File hosting**: Dropbox via 302 redirect from `https://updater.swginfinity.com/files/live/{filename}`
- **Launcher update API**: `https://updater.swginfinity.com/api/v2/launcher/update-check`
- **Fallback API**: `https://api2.swginfinity.com/api/v2/launcher/update-check`
- **Main API**: `https://api.swginfinity.com` (authenticated endpoints, not used by download script)

## download-game.sh

Fetches manifest, downloads all required files with `curl -L` (follows Dropbox redirects), verifies MD5 hashes. Resumable—skips files that pass verification on rerun. Default target: `./game-files/`.

**Dependencies**: `curl`, `python3`, `hashlib` (stdlib)

## The Launcher Problem

The Infinity Launcher (v0.2.22) is a Tauri/Rust app using WebView2 for its UI. Under Wine (CrossOver 26.2.0 / Wine 11.0), WebView2's COM initialization crashes with a page fault in ole32.dll. WebView2 processes spawn but the launcher dies during the COM handshake. No combination of runtime installs (WebView2 Evergreen, VC++ 2015, etc.) fixes it—the issue is in Wine's ole32 COM bridge, not a missing dependency.

The game client (`SwgClient_r.exe`) runs fine under Wine. The launcher is just a download/patch manager—bypassing it loses nothing.

## Sikarugir

Free, open-source Wine wrapper for macOS. Successor to Whisky. Installs via `brew install --cask Sikarugir-App/sikarugir/sikarugir`. Creates native `.app` wrappers with built-in DXMT (DirectX-to-Metal). The game client runs inside a Sikarugir wrapper.

- **Wrapper location**: `~/Applications/Sikarugir/SWG Infinity.app`
- **C: drive**: `~/Applications/Sikarugir/SWG Infinity.app/Contents/SharedSupport/prefix/drive_c/`
- **Game files**: `C:\SWG Infinity\` inside the wrapper
- **DirectX 9**: Installed via Winetricks `d3dx9` (not the manual redistributable—the extractor dialog doesn't surface under Wine)
- **DXMT**: Must be enabled in Configure for GPU performance on Apple Silicon

## Project Thorn

Interactive Imperial Intelligence terminal demo in `demos/project-thorn/`. Built from 2003-era SWG character bios (Vorian Ducal / Jiff Gorda). Single HTML file, no dependencies. Separate from the game setup—included for historical context. See `demos/project-thorn/README.md` for full docs.

## Conventions

- README voice follows Tom's style: connected em dashes (—), no hedging, declarative prose
- No Co-Authored-By trailers in commits
- Screenshots use descriptive kebab-case filenames
