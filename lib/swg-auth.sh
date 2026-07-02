#!/usr/bin/env bash
# Authentication flow, config writing, and live.cfg patching.

SWG_API_BASE="https://my.swginfinity.com/api/auth"

swg_login() {
    echo "SWG Infinity Login"
    echo "==================="
    echo ""

    read -rp "Username: " username
    read -rsp "Password: " password
    echo ""

    echo "Authenticating..."

    local tmpfile
    tmpfile=$(mktemp)
    chmod 600 "$tmpfile"
    trap 'rm -f "$tmpfile"' EXIT RETURN

    local http_code body
    http_code=$(python3 -c "import json,sys; print(json.dumps({'username': sys.argv[1], 'password': sys.argv[2], 'mfaEnabled': True, 'sessionDurationDays': 30}))" "$username" "$password" \
        | curl -s -o "$tmpfile" -w '%{http_code}' -X POST "$SWG_API_BASE/login" \
            -H "Content-Type: application/json" \
            --data-binary @-)
    body=$(cat "$tmpfile")

    if [ "$http_code" != "200" ]; then
        local error
        error=$(echo "$body" | swg_json_get "error" 2>/dev/null || echo "HTTP $http_code")
        [ "$error" = "" ] && error=$(echo "$body" | swg_json_get "message" 2>/dev/null || echo "HTTP $http_code")
        swg_die "Login failed: $error"
    fi

    local mfa_token access_token
    mfa_token=$(echo "$body" | swg_json_get "mfaToken" 2>/dev/null)
    access_token=$(echo "$body" | swg_json_get "accessToken" 2>/dev/null)

    if [ -n "$mfa_token" ] && [ -z "$access_token" ]; then
        echo "MFA required — check your email for a verification code."
        swg_json_build mfaToken "$mfa_token" \
            | curl -s -X POST "$SWG_API_BASE/email-code" \
                -H "Content-Type: application/json" \
                --data-binary @- > /dev/null

        read -rp "Enter code: " mfa_code

        http_code=$(swg_json_build mfaToken "$mfa_token" code "$mfa_code" \
            | curl -s -o "$tmpfile" -w '%{http_code}' -X POST "$SWG_API_BASE/verify-email-code" \
                -H "Content-Type: application/json" \
                --data-binary @-)
        body=$(cat "$tmpfile")

        if [ "$http_code" != "200" ]; then
            local error
            error=$(echo "$body" | swg_json_get "error" 2>/dev/null || echo "HTTP $http_code")
            [ "$error" = "" ] && error=$(echo "$body" | swg_json_get "message" 2>/dev/null || echo "HTTP $http_code")
            swg_die "MFA verification failed: $error"
        fi

        access_token=$(echo "$body" | swg_json_get "accessToken" 2>/dev/null)
    fi

    [ -z "$access_token" ] && swg_die "No access token received."

    echo "Authenticated."
    swg_discover_server "$access_token"
}

swg_discover_server() {
    local token="$1"
    echo "Fetching server info..."

    local auth_cfg
    auth_cfg=$(mktemp)
    chmod 600 "$auth_cfg"
    printf 'header = "Authorization: Bearer %s"\n' "$token" > "$auth_cfg"
    trap 'rm -f "$auth_cfg"' RETURN

    local login_host="" login_port=""
    for endpoint in \
        "https://api.swginfinity.com/api/v2/launcher/server-config" \
        "https://api.swginfinity.com/api/v2/game/config" \
        "https://api.swginfinity.com/api/v2/server/connection" \
        "https://api.swginfinity.com/api/v2/launcher/launch"; do

        local resp code
        resp=$(curl -s -w "\n%{http_code}" -K "$auth_cfg" "$endpoint" \
            -H "Content-Type: application/json")
        code=$(echo "$resp" | tail -1)

        if [ "$code" = "200" ]; then
            local server_body
            server_body=$(echo "$resp" | sed '$d')
            login_host=$(echo "$server_body" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for key in ['loginHost', 'loginServerAddress', 'host', 'server', 'address', 'gameServer']:
    if key in d: print(d[key]); sys.exit(0)
for v in d.values():
    if isinstance(v, dict):
        for key in ['loginHost', 'loginServerAddress', 'host', 'server', 'address']:
            if key in v: print(v[key]); sys.exit(0)
print('')
" 2>/dev/null)
            login_port=$(echo "$server_body" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for key in ['loginPort', 'loginServerPort', 'port']:
    if key in d: print(d[key]); sys.exit(0)
for v in d.values():
    if isinstance(v, dict):
        for key in ['loginPort', 'loginServerPort', 'port']:
            if key in v: print(v[key]); sys.exit(0)
print('')
" 2>/dev/null)
            [ -n "$login_host" ] && break
        fi
    done

    login_host="${login_host:-game.swginfinity.com}"
    login_port="${login_port:-44453}"

    echo "Server: $login_host:$login_port"
    swg_write_configs "$login_host" "$login_port"
}

swg_write_configs() {
    local host="$1" port="$2"

    cat > "$GAME_DIR/swgemu_login.cfg" << EOF
[ClientGame]
loginServerAddress0=$host
loginServerPort0=$port
autoConnectToLoginServer=true
EOF
    echo "Wrote: swgemu_login.cfg"

    cat > "$GAME_DIR/swgemu.cfg" << 'EOF'
.include "options.cfg"
.include "swgemu_live.cfg"
.include "swgemu_login.cfg"
.include "user_infinity.cfg"
.include "user.cfg"
EOF
    echo "Wrote: swgemu.cfg"

    swg_patch_live_cfg
}

swg_patch_live_cfg() {
    local live_cfg="$GAME_DIR/swgemu_live.cfg"
    [ -f "$live_cfg" ] || return 0

    if ! grep -q 'bottom\.tre' "$live_cfg"; then
        sed -i '' '/searchTree_00_30=/a\
    searchTree_00_01=infinity_xmas.tre\
    searchTree_00_00=bottom.tre
' "$live_cfg"
        echo "Patched: swgemu_live.cfg (added base .tre entries)"
    fi
}

swg_cmd_login() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: swg login"
        echo "Authenticate with SWG Infinity and write game config files."
        return 0
    fi
    swg_require "$GAME_DIR" "Game directory"
    swg_login
    echo ""
    echo "Ready to launch."
}
