#!/usr/bin/env bash
# Status, config, and winetricks management.

swg_cmd_status() {
    swg_require "$WRAPPER" "Wrapper"

    echo "SWG Infinity Status"
    echo "==================="
    echo ""

    # Wine
    local wine_ver
    wine_ver=$("$WINE" --version 2>/dev/null || echo "not found")
    echo "Wine:      $wine_ver"

    # Renderer
    local renderer="unknown"
    for r in DXMT DXVK D9VK D3DMETAL CNC_DDRAW; do
        local val
        val=$(swg_plist_read "$r" 2>/dev/null || true)
        if [ "$val" = "1" ]; then
            renderer="$r"
            break
        fi
    done
    echo "Renderer:  $renderer"

    # Sync
    local esync msync
    esync=$(swg_plist_read "WINEESYNC" 2>/dev/null || echo "unset")
    msync=$(swg_plist_read "WINEMSYNC" 2>/dev/null || echo "unset")
    echo "ESYNC:     $esync"
    echo "MSYNC:     $msync"

    # Files
    if [ -d "$GAME_DIR" ]; then
        local tre_count cfg_count
        tre_count=$(find "$GAME_DIR" -maxdepth 1 -name "*.tre" 2>/dev/null | wc -l | tr -d ' ')
        cfg_count=$(find "$GAME_DIR" -maxdepth 1 -name "*.cfg" 2>/dev/null | wc -l | tr -d ' ')
        echo "TRE files: $tre_count"
        echo "CFG files: $cfg_count"
    else
        echo "Game dir:  NOT FOUND"
    fi

    # Server
    echo ""
    echo "Server reachability:"
    if curl -s --connect-timeout 5 "https://my.swginfinity.com" > /dev/null 2>&1; then
        echo "  my.swginfinity.com     — reachable"
    else
        echo "  my.swginfinity.com     — unreachable"
    fi
    if curl -s --connect-timeout 5 "https://updater.swginfinity.com/manifest.json" > /dev/null 2>&1; then
        echo "  updater (manifest)     — reachable"
    else
        echo "  updater (manifest)     — unreachable"
    fi

    # Wineserver
    if pgrep -f "wineserver" > /dev/null 2>&1; then
        echo "  wineserver             — running"
    else
        echo "  wineserver             — not running"
    fi
}

swg_cmd_config() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: swg config [key [value]]"
        echo "Read/write Sikarugir plist flags. No args shows all flags."
        return 0
    fi
    local key="${1:-}" value="${2:-}"

    if [ -z "$key" ]; then
        echo "Sikarugir Plist Flags"
        echo "====================="
        echo ""
        for k in DXMT DXVK D9VK D3DMETAL CNC_DDRAW WINEESYNC WINEMSYNC WINEDEBUG MOLTENVKCX METAL_HUD FASTMATH "Debug Mode" "Skip Gecko" "Skip Mono"; do
            local val
            val=$(swg_plist_read "$k" 2>/dev/null || echo "unset")
            printf "  %-16s = %s\n" "$k" "$val"
        done
        return 0
    fi

    if [ -z "$value" ]; then
        local val
        val=$(swg_plist_read "$key" 2>/dev/null || echo "unset")
        echo "$key = $val"
    else
        swg_plist_write "$key" "$value"
        echo "$key = $value"
    fi
}

swg_cmd_winetricks() {
    local verb="${1:-}"
    if [ -z "$verb" ]; then
        echo "Usage: swg winetricks <verb> [verb2 ...]"
        echo ""
        echo "Examples:"
        echo "  swg winetricks vcrun2019"
        echo "  swg winetricks d3dx9"
        echo "  swg winetricks list-installed"
        return 1
    fi

    swg_require "$WINETRICKS_BIN" "winetricks"
    swg_setup_wine_env

    "$WINETRICKS_BIN" "$@"
}
