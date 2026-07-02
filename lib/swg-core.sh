#!/usr/bin/env bash
# Core constants and helpers for the swg CLI.

WRAPPER="$HOME/Applications/Sikarugir/SWG Infinity.app"
WINE="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
WINESERVER="$WRAPPER/Contents/SharedSupport/wine/bin/wineserver"
PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
GAME_DIR="$PREFIX/drive_c/SWG Infinity"
PLIST="$WRAPPER/Contents/Info.plist"
WINETRICKS_BIN="$WRAPPER/Contents/SharedSupport/winetricks"
WINE_LOG_DIR="$WRAPPER/Contents/SharedSupport/Logs"

SWG_LOG_FILE=""

swg_log() {
    local msg
    msg="$(printf '[%s] %s' "$(date +%H:%M:%S)" "$*")"
    echo "$msg"
    if [ -n "$SWG_LOG_FILE" ]; then
        echo "$msg" >> "$SWG_LOG_FILE"
    fi
}

swg_die() {
    swg_log "FATAL: $*"
    exit 1
}

swg_require() {
    local path="$1" label="${2:-$1}"
    [ -e "$path" ] || swg_die "$label not found: $path"
}

swg_plist_read() {
    /usr/libexec/PlistBuddy -c "Print ':$1'" "$PLIST" 2>/dev/null
}

swg_plist_write() {
    local key="$1" val="$2"
    local escaped_val="${val//\'/\\\'}"
    if /usr/libexec/PlistBuddy -c "Print ':$key'" "$PLIST" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set ':$key' '${escaped_val}'" "$PLIST"
    else
        /usr/libexec/PlistBuddy -c "Add ':$key' string '${escaped_val}'" "$PLIST"
    fi
}

swg_json_get() {
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1], ''))" "$1"
}

swg_json_build() {
    python3 -c "import json,sys; print(json.dumps(dict(zip(sys.argv[1::2], sys.argv[2::2]))))" "$@"
}
