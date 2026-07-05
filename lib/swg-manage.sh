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

# Display/graphics settings in options.cfg — the file the game client reads
# for window mode, resolution, and renderer choices.
_SWG_OPTIONS_KEYS="width height windowed borderless refresh safe-renderer antialias skip-intro"

_swg_options_map() {
    # friendly-name -> "Section iniKey"
    case "$1" in
        width)         echo "ClientGraphics screenWidth" ;;
        height)        echo "ClientGraphics screenHeight" ;;
        windowed)      echo "ClientGraphics windowed" ;;
        borderless)    echo "ClientGraphics borderlessWindow" ;;
        safe-renderer) echo "ClientGraphics useSafeRenderer" ;;
        refresh)       echo "Direct3d9 fullscreenRefreshRate" ;;
        antialias)     echo "Direct3d9 antiAlias" ;;
        skip-intro)    echo "ClientGame skipIntro" ;;
        *)             return 1 ;;
    esac
}

_swg_options_edit() {
    local section="$1" key="$2" value="$3"
    python3 - "$GAME_DIR/options.cfg" "$section" "$key" "$value" << 'EOF'
import sys
path, section, key, value = sys.argv[1:5]
raw = open(path, 'rb').read()
eol = b'\r\n' if b'\r\n' in raw else b'\n'
lines = raw.split(eol)
out, in_section, done = [], False, False
for line in lines:
    stripped = line.strip()
    if stripped.startswith(b'[') and stripped.endswith(b']'):
        if in_section and not done:
            out.append(b'\t' + key.encode() + b'=' + value.encode())
            done = True
        in_section = stripped == b'[' + section.encode() + b']'
        out.append(line)
        continue
    if in_section and stripped.split(b'=')[0].strip() == key.encode():
        # replace the first occurrence, drop duplicates (game uses last-wins)
        if not done:
            out.append(b'\t' + key.encode() + b'=' + value.encode())
            done = True
        continue
    out.append(line)
if not done:
    if out and out[-1] == b'':
        out.pop()
    if not in_section:
        out.append(b'')
        out.append(b'[' + section.encode() + b']')
    out.append(b'\t' + key.encode() + b'=' + value.encode())
    out.append(b'')
open(path, 'wb').write(eol.join(out))
EOF
}

_swg_options_read() {
    local section="$1" key="$2"
    python3 - "$GAME_DIR/options.cfg" "$section" "$key" << 'EOF'
import sys
path, section, key = sys.argv[1:4]
in_section, value = False, None
# last match wins — mirrors the game's merge behavior for duplicate keys
for line in open(path, 'rb').read().replace(b'\r\n', b'\n').split(b'\n'):
    s = line.strip()
    if s.startswith(b'[') and s.endswith(b']'):
        in_section = s == b'[' + section.encode() + b']'
        continue
    if in_section and b'=' in s and s.split(b'=')[0].strip() == key.encode():
        value = s.split(b'=', 1)[1].strip().decode()
if value is not None:
    print(value)
EOF
}

swg_cmd_options() {
    swg_require "$GAME_DIR/options.cfg" "options.cfg"

    case "${1:-}" in
        --help|-h)
            echo "Usage: swg options [key [value]]"
            echo "       swg options resolution <WxH>"
            echo "Read/write game display settings in options.cfg."
            echo ""
            echo "Keys: $_SWG_OPTIONS_KEYS"
            echo ""
            echo "Examples:"
            echo "  swg options                    # show all"
            echo "  swg options windowed 1"
            echo "  swg options resolution 1920x1080"
            echo "  swg options refresh 60"
            return 0
            ;;
        "")
            echo "Game Display Settings (options.cfg)"
            echo "===================================="
            local k mapped val
            for k in $_SWG_OPTIONS_KEYS; do
                mapped=$(_swg_options_map "$k")
                val=$(_swg_options_read ${mapped:-x x})
                printf "  %-14s = %s\n" "$k" "${val:-unset}"
            done
            return 0
            ;;
        resolution)
            local res="${2:-}"
            if ! echo "$res" | grep -qE '^[0-9]+x[0-9]+$'; then
                swg_die "Usage: swg options resolution <WxH>  (e.g. 1920x1080)"
            fi
            _swg_options_edit ClientGraphics screenWidth "${res%x*}"
            _swg_options_edit ClientGraphics screenHeight "${res#*x}"
            echo "resolution = $res"
            return 0
            ;;
    esac

    local key="$1" value="${2:-}" mapped
    if ! mapped=$(_swg_options_map "$key"); then
        swg_die "Unknown key: $key (valid: $_SWG_OPTIONS_KEYS, resolution)"
    fi

    if [ -z "$value" ]; then
        local val
        val=$(_swg_options_read $mapped)
        echo "$key = ${val:-unset}"
    else
        _swg_options_edit $mapped "$value"
        echo "$key = $value"
    fi
}

# Toggle the in-game login-screen skip (session auto-login). Affects only
# whether `swg launch --login` writes user_autologin.cfg — Keychain
# credential storage and MFA-skip via refresh token are unaffected.
swg_cmd_autologin() {
    case "${1:-}" in
        on)
            swg_user_config_set SWG_AUTOLOGIN 1
            echo "autologin = on"
            ;;
        off)
            swg_user_config_set SWG_AUTOLOGIN 0
            echo "autologin = off"
            ;;
        ""|status)
            local state="${SWG_AUTOLOGIN:-1}"
            [ "$state" = "1" ] && echo "autologin = on (default)" || echo "autologin = off"
            ;;
        --help|-h|*)
            echo "Usage: swg autologin [on|off|status]"
            echo "Enable/disable skipping the in-game login screen during 'swg launch --login'."
            echo "Setting persists in $SWG_USER_CONFIG; override per-run with SWG_AUTOLOGIN=0/1."
            ;;
    esac
}

# Pin the login server host/port, overriding API discovery. Use when the
# auto-discovered/fallback address is wrong (e.g. Infinity provides the real
# endpoint directly). Persists in the user config.
swg_cmd_server() {
    case "${1:-}" in
        --help|-h)
            echo "Usage: swg server <host[:port]>   pin login server"
            echo "       swg server                 show current pin"
            echo "       swg server --clear         revert to API discovery"
            echo ""
            echo "Overrides the loginServerAddress/Port written by 'swg login'."
            return 0
            ;;
        "")
            if [ -n "${SWG_LOGIN_HOST:-}" ]; then
                echo "login server = $SWG_LOGIN_HOST:${SWG_LOGIN_PORT:-14453} (pinned)"
            else
                echo "login server = (auto-discovery, fallback game.swginfinity.com:14453)"
            fi
            return 0
            ;;
        --clear)
            swg_user_config_set SWG_LOGIN_HOST ""
            swg_user_config_set SWG_LOGIN_PORT ""
            echo "login server pin cleared — reverting to discovery"
            return 0
            ;;
    esac

    local host="${1%%:*}" port=""
    case "$1" in *:*) port="${1##*:}" ;; esac
    [ -z "$host" ] && swg_die "Empty host — use <host> or <host:port>"
    [ -z "$port" ] && port="14453"
    if ! echo "$port" | grep -qE '^[0-9]+$'; then
        swg_die "Invalid port: $port"
    fi
    swg_user_config_set SWG_LOGIN_HOST "$host"
    swg_user_config_set SWG_LOGIN_PORT "$port"
    echo "login server = $host:$port (pinned)"
    echo "Run 'swg login' to write it into the game config."
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
