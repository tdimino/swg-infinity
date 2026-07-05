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

# User-level CLI settings (KEY=VALUE, shell-sourceable). Env vars win over
# the file: `SWG_AUTOLOGIN=0 swg launch` overrides a stored setting.
SWG_USER_CONFIG="$HOME/.config/swg/config"
# Snapshot env-provided settings, source the file, then let any non-empty env
# value win — so `SWG_AUTOLOGIN=0 swg launch` overrides the stored setting.
_swg_env_snapshot=""
for _k in SWG_AUTOLOGIN SWG_MEMORY_MB SWG_LOGIN_HOST SWG_LOGIN_PORT; do
    _swg_env_snapshot+="$_k=$(eval "printf '%s' \"\${$_k:-}\"")"$'\n'
done
if [ -f "$SWG_USER_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$SWG_USER_CONFIG"
fi
while IFS='=' read -r _k _v; do
    [ -n "$_k" ] && [ -n "$_v" ] && eval "$_k=\$_v"
done <<< "$_swg_env_snapshot"
unset _k _v _swg_env_snapshot

swg_user_config_set() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "$SWG_USER_CONFIG")"
    touch "$SWG_USER_CONFIG"
    # rewrite rather than sed — value stays literal whatever characters it holds
    local rest
    rest=$(grep -v "^${key}=" "$SWG_USER_CONFIG" 2>/dev/null || true)
    {
        [ -n "$rest" ] && printf '%s\n' "$rest"
        printf '%s=%s\n' "$key" "$value"
    } > "$SWG_USER_CONFIG"
}

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

# JSON builder for secrets: keys as args, one value per line on stdin —
# values never appear on any process's argv.
swg_json_build_secret() {
    python3 -c "
import json, sys
keys = sys.argv[1:]
vals = sys.stdin.read().split('\n')
print(json.dumps(dict(zip(keys, vals))))" "$@"
}

# Convert a file to CRLF line endings in place — game configs match what the
# Windows launcher writes.
swg_crlf_file() {
    python3 -c "
import sys
p = sys.argv[1]
d = open(p, 'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
open(p, 'wb').write(d)" "$1"
}

# Top-level key names of a JSON object on stdin — for API response
# shape discovery without ever logging values.
swg_json_keys() {
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('(non-JSON)')
    raise SystemExit
if isinstance(d, dict):
    parts = []
    for k, v in d.items():
        if isinstance(v, dict):
            parts.append(k + '{' + ','.join(v.keys()) + '}')
        else:
            parts.append(k)
    print(', '.join(parts))
else:
    print('(' + type(d).__name__ + ')')
"
}
