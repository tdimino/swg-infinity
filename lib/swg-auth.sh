#!/usr/bin/env bash
# Authentication flow, config writing, and live.cfg patching.

SWG_API_BASE="https://my.swginfinity.com/api/auth"
SWG_KEYCHAIN_SERVICE="swg-infinity"
# Discovered 2026-07-05: POST {refreshToken} → {accessToken, refreshToken, sessionId}
SWG_REFRESH_ENDPOINT="$SWG_API_BASE/refresh"

# Log top-level JSON key names (never values) when SWG_DEBUG_API=1.
_swg_api_debug() {
    [ "${SWG_DEBUG_API:-0}" = "1" ] || return 0
    local label="$1" body="$2"
    swg_log "API [$label] keys: $(echo "$body" | swg_json_keys)"
}

swg_keychain_get() {
    local field="$1"
    security find-generic-password -s "$SWG_KEYCHAIN_SERVICE" -a "$field" -w 2>/dev/null
}

swg_keychain_set() {
    local field="$1" value="$2"
    case "$value" in *$'\n'*) swg_die "Refusing to store multi-line value in Keychain ($field)" ;; esac
    security delete-generic-password -s "$SWG_KEYCHAIN_SERVICE" -a "$field" >/dev/null 2>&1 || true
    # security -i reads the command from stdin — the secret never hits argv
    local escaped="${value//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf 'add-generic-password -s "%s" -a "%s" -w "%s"\n' \
        "$SWG_KEYCHAIN_SERVICE" "$field" "$escaped" | security -i
}

swg_keychain_delete() {
    local field
    for field in username password refresh-token token-expires; do
        security delete-generic-password -s "$SWG_KEYCHAIN_SERVICE" -a "$field" >/dev/null 2>&1 || true
    done
    echo "Removed stored credentials from Keychain."
}

_swg_auth_tmpfile=""
_swg_auth_cfg=""
_swg_auth_username=""
_swg_session_id=""

_swg_auth_cleanup() {
    rm -f "${_swg_auth_tmpfile:-}" "${_swg_auth_cfg:-}"
    _swg_auth_tmpfile=""
    _swg_auth_cfg=""
}

# Persist the rotated refresh token — only when the user opted into Keychain
# storage (stored username present).
_swg_store_refresh_token() {
    local body="$1" stored_user rt exp
    stored_user=$(swg_keychain_get "username" || true)
    [ -n "$stored_user" ] || return 0
    rt=$(echo "$body" | swg_json_get "refreshToken" 2>/dev/null || true)
    exp=$(echo "$body" | swg_json_get "expiresAt" 2>/dev/null || true)
    [ -n "$rt" ] && swg_keychain_set "refresh-token" "$rt"
    [ -n "$exp" ] && swg_keychain_set "token-expires" "$exp"
    return 0
}

# Try to mint an access token from the stored refresh token, skipping the
# credential+MFA flow. Sets _swg_refresh_access_token on success.
_swg_refresh_access_token=""
_swg_try_refresh() {
    [ -n "$SWG_REFRESH_ENDPOINT" ] || return 1
    local refresh_token
    refresh_token=$(swg_keychain_get "refresh-token" || true)
    [ -n "$refresh_token" ] || return 1

    _swg_auth_tmpfile=$(mktemp)
    chmod 600 "$_swg_auth_tmpfile"
    trap '_swg_auth_cleanup' EXIT

    local http_code body
    http_code=$(printf '%s' "$refresh_token" | swg_json_build_secret refreshToken \
        | curl -s -o "$_swg_auth_tmpfile" -w '%{http_code}' -X POST "$SWG_REFRESH_ENDPOINT" \
            -H "Content-Type: application/json" \
            --data-binary @-) || http_code="000"
    body=$(cat "$_swg_auth_tmpfile")
    _swg_auth_cleanup
    trap - EXIT

    [ "$http_code" = "200" ] || return 1
    _swg_api_debug "refresh" "$body"
    _swg_refresh_access_token=$(echo "$body" | swg_json_get "accessToken" 2>/dev/null)
    [ -n "$_swg_refresh_access_token" ] || return 1
    _swg_session_id=$(echo "$body" | swg_json_get "sessionId" 2>/dev/null)
    _swg_store_refresh_token "$body"
    return 0
}

# Discovery aid: probe candidate refresh endpoints with the fresh token and
# log HTTP codes + response key names. SWG_DEBUG_API=1 only.
_swg_probe_refresh_endpoints() {
    local body="$1" rt ep code probe_body
    rt=$(echo "$body" | swg_json_get "refreshToken" 2>/dev/null)
    if [ -z "$rt" ]; then
        swg_log "API probe: no refreshToken in auth response — skipping refresh probes"
        return 0
    fi
    for ep in "$SWG_API_BASE/refresh" "$SWG_API_BASE/refresh-token"; do
        _swg_auth_tmpfile=$(mktemp)
        chmod 600 "$_swg_auth_tmpfile"
        trap '_swg_auth_cleanup' EXIT
        code=$(printf '%s' "$rt" | swg_json_build_secret refreshToken \
            | curl -s -o "$_swg_auth_tmpfile" -w '%{http_code}' -X POST "$ep" \
                -H "Content-Type: application/json" \
                --data-binary @-) || code="000"
        probe_body=$(cat "$_swg_auth_tmpfile")
        _swg_auth_cleanup
        trap - EXIT
        swg_log "API probe [$ep]: HTTP $code"
        if [ "$code" = "200" ]; then
            _swg_api_debug "refresh-probe" "$probe_body"
            _swg_store_refresh_token "$probe_body"
        fi
    done
}

swg_login() {
    local save_creds=false
    if [ "${1:-}" = "--save" ]; then
        save_creds=true
    fi

    echo "SWG Infinity Login"
    echo "==================="
    echo ""

    local username password
    username=$(swg_keychain_get "username" || true)
    password=$(swg_keychain_get "password" || true)
    _swg_auth_username="$username"

    if [ -n "$username" ] && _swg_try_refresh; then
        echo "Session refreshed from Keychain — no MFA needed."
        echo "Authenticated."
        swg_discover_server "$_swg_refresh_access_token"
        return 0
    fi

    if [ -n "$username" ] && [ -n "$password" ]; then
        echo "Using stored credentials for $username"
    else
        read -rp "Username: " username
        read -rsp "Password: " password
        echo ""
        _swg_auth_username="$username"
    fi

    echo "Authenticating..."

    _swg_auth_tmpfile=$(mktemp)
    chmod 600 "$_swg_auth_tmpfile"
    trap '_swg_auth_cleanup' EXIT

    local http_code body
    http_code=$(printf '%s\n%s' "$username" "$password" | python3 -c "
import json, sys
u, p = sys.stdin.read().split('\n', 1)
print(json.dumps({'username': u, 'password': p, 'mfaEnabled': True, 'sessionDurationDays': 30}))" \
        | curl -s -o "$_swg_auth_tmpfile" -w '%{http_code}' -X POST "$SWG_API_BASE/login" \
            -H "Content-Type: application/json" \
            --data-binary @-)
    body=$(cat "$_swg_auth_tmpfile")

    if [ "$http_code" != "200" ]; then
        local error
        error=$(echo "$body" | swg_json_get "error" 2>/dev/null || echo "HTTP $http_code")
        [ "$error" = "" ] && error=$(echo "$body" | swg_json_get "message" 2>/dev/null || echo "HTTP $http_code")
        swg_die "Login failed: $error"
    fi

    _swg_api_debug "login" "$body"

    local mfa_token access_token
    mfa_token=$(echo "$body" | swg_json_get "mfaToken" 2>/dev/null)
    access_token=$(echo "$body" | swg_json_get "accessToken" 2>/dev/null)

    if [ -n "$mfa_token" ] && [ -z "$access_token" ]; then
        echo "MFA required — check your email for a verification code."
        printf '%s' "$mfa_token" | swg_json_build_secret mfaToken \
            | curl -s -X POST "$SWG_API_BASE/email-code" \
                -H "Content-Type: application/json" \
                --data-binary @- > /dev/null

        read -rp "Enter code: " mfa_code

        http_code=$(printf '%s\n%s' "$mfa_token" "$mfa_code" | swg_json_build_secret mfaToken code \
            | curl -s -o "$_swg_auth_tmpfile" -w '%{http_code}' -X POST "$SWG_API_BASE/verify-email-code" \
                -H "Content-Type: application/json" \
                --data-binary @-)
        body=$(cat "$_swg_auth_tmpfile")

        if [ "$http_code" != "200" ]; then
            local error
            error=$(echo "$body" | swg_json_get "error" 2>/dev/null || echo "HTTP $http_code")
            [ "$error" = "" ] && error=$(echo "$body" | swg_json_get "message" 2>/dev/null || echo "HTTP $http_code")
            swg_die "MFA verification failed: $error"
        fi

        _swg_api_debug "verify-email-code" "$body"
        access_token=$(echo "$body" | swg_json_get "accessToken" 2>/dev/null)
    fi

    [ -z "$access_token" ] && swg_die "No access token received."
    _swg_session_id=$(echo "$body" | swg_json_get "sessionId" 2>/dev/null)

    _swg_auth_cleanup
    trap - EXIT

    if [ "$save_creds" = true ]; then
        swg_keychain_set "username" "$username"
        swg_keychain_set "password" "$password"
        echo "Credentials saved to Keychain."
    fi

    _swg_store_refresh_token "$body"
    if [ "${SWG_DEBUG_API:-0}" = "1" ]; then
        _swg_probe_refresh_endpoints "$body"
    fi

    echo "Authenticated."
    swg_discover_server "$access_token"
}

swg_discover_server() {
    local token="$1"

    # A pinned login server (from `swg server <host:port>` / SWG_LOGIN_HOST)
    # wins over API discovery and the built-in fallback.
    if [ -n "${SWG_LOGIN_HOST:-}" ]; then
        echo "Using pinned login server: $SWG_LOGIN_HOST:${SWG_LOGIN_PORT:-14453}"
        swg_write_configs "$SWG_LOGIN_HOST" "${SWG_LOGIN_PORT:-14453}"
        return 0
    fi

    echo "Fetching server info..."

    _swg_auth_cfg=$(mktemp)
    chmod 600 "$_swg_auth_cfg"
    printf 'header = "Authorization: Bearer %s"\n' "$token" > "$_swg_auth_cfg"
    trap '_swg_auth_cleanup' EXIT

    # The launcher's real endpoint (recovered from its frontend bundle):
    # POST /game/session → {host, port, sessionId, serverEnv}
    local endpoint="https://api2.swginfinity.com/api/v2/game/session"
    local login_host="" login_port="" resp code server_body
    resp=$(printf '{"server":"live"}' \
        | curl -s -w "\n%{http_code}" -K "$_swg_auth_cfg" -X POST "$endpoint" \
            -H "Content-Type: application/json" \
            --data-binary @-) || resp=$'\n000'
    code=$(echo "$resp" | tail -1)
    [ "${SWG_DEBUG_API:-0}" = "1" ] && swg_log "API [$endpoint]: HTTP $code"

    if [ "$code" = "200" ]; then
        server_body=$(echo "$resp" | sed '$d')
        _swg_api_debug "game/session" "$server_body"
        login_host=$(echo "$server_body" | swg_json_get "host" 2>/dev/null || true)
        login_port=$(echo "$server_body" | swg_json_get "port" 2>/dev/null || true)
        if [ -z "$_swg_session_id" ]; then
            _swg_session_id=$(echo "$server_body" | swg_json_get "sessionId" 2>/dev/null || true)
            [ -n "$_swg_session_id" ] && swg_log "Session ID acquired (auto-login enabled)"
        fi
    fi

    # Fallback: the launcher frontend's hardcoded LIVE server
    login_host="${login_host:-game.swginfinity.com}"
    login_port="${login_port:-14453}"

    echo "Server: $login_host:$login_port"
    _swg_auth_cleanup
    trap - EXIT
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
    swg_crlf_file "$GAME_DIR/swgemu_login.cfg"
    echo "Wrote: swgemu_login.cfg"

    cat > "$GAME_DIR/swgemu.cfg" << 'EOF'
.include "options.cfg"
.include "swgemu_live.cfg"
.include "swgemu_login.cfg"
.include "user_autologin.cfg"
.include "user_infinity.cfg"
.include "user.cfg"
EOF
    swg_crlf_file "$GAME_DIR/swgemu.cfg"
    echo "Wrote: swgemu.cfg"

    swg_patch_live_cfg
}

# Session auto-login include — written just before launch when a sessionId
# was acquired, chmod 600, deleted after the game exits. Missing include is
# tolerated by the client, so manual-login launches are unaffected.
swg_write_autologin_cfg() {
    local cfg="$GAME_DIR/user_autologin.cfg"
    : > "$cfg"
    chmod 600 "$cfg"
    cat >> "$cfg" << EOF
[ClientGame]
	loginClientID=$_swg_auth_username
	loginClientPassword=$_swg_session_id
	sessionId=$_swg_session_id
	autoConnectToLoginServer=true
EOF
    swg_crlf_file "$cfg"
    echo "Wrote: user_autologin.cfg (session auto-login)"
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
    case "${1:-}" in
        --help|-h)
            echo "Usage: swg login [--save] [--forget]"
            echo "Authenticate with SWG Infinity and write game config files."
            echo ""
            echo "Options:"
            echo "  --save    Store credentials in macOS Keychain"
            echo "  --forget  Remove stored credentials from Keychain"
            return 0
            ;;
        --forget)
            swg_keychain_delete
            return 0
            ;;
    esac
    swg_require "$GAME_DIR" "Game directory"
    swg_login "$@"
    echo ""
    echo "Ready to launch."
}
