#!/usr/bin/env bash
#
# Authenticate with SWG Infinity and write swgemu_login.cfg.
# Replicates the launcher's auth flow for Mac/Linux users.
#
# Usage:
#   ./login.sh [game-directory]
#
# Default game directory: the Sikarugir wrapper's SWG Infinity folder.

set -euo pipefail

DEFAULT_DIR="$HOME/Applications/Sikarugir/SWG Infinity.app/Contents/SharedSupport/prefix/drive_c/SWG Infinity"
GAME_DIR="${1:-$DEFAULT_DIR}"
API_BASE="https://my.swginfinity.com/api/auth"

if [ ! -d "$GAME_DIR" ]; then
    echo "Error: Game directory not found: $GAME_DIR"
    exit 1
fi

echo "SWG Infinity Login"
echo "==================="
echo ""

read -rp "Username: " USERNAME
read -rsp "Password: " PASSWORD
echo ""

echo "Authenticating..."

LOGIN_JSON=$(python3 - "$USERNAME" "$PASSWORD" <<'PYEOF'
import json, sys
print(json.dumps({"username": sys.argv[1], "password": sys.argv[2], "mfaEnabled": True, "sessionDurationDays": 30}))
PYEOF
)

RESPONSE=$(curl -s -o /tmp/swg_login_response.json -w '%{http_code}' -X POST "$API_BASE/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_JSON")

HTTP_CODE="$RESPONSE"
BODY=$(cat /tmp/swg_login_response.json)

if [ "$HTTP_CODE" != "200" ]; then
    ERROR=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error', d.get('message', 'Unknown error')))" 2>/dev/null || echo "HTTP $HTTP_CODE")
    echo "Login failed: $ERROR"
    exit 1
fi

# Check if MFA is required
MFA_TOKEN=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('mfaToken', ''))" 2>/dev/null)
ACCESS_TOKEN=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('accessToken', ''))" 2>/dev/null)

if [ -n "$MFA_TOKEN" ] && [ -z "$ACCESS_TOKEN" ]; then
    echo "MFA required — check your email for a verification code."

    # Request the email code
    curl -s -X POST "$API_BASE/email-code" \
        -H "Content-Type: application/json" \
        -d "{\"mfaToken\": \"$MFA_TOKEN\"}" > /dev/null

    read -rp "Enter code: " MFA_CODE

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/verify-email-code" \
        -H "Content-Type: application/json" \
        -d "{\"mfaToken\": \"$MFA_TOKEN\", \"code\": \"$MFA_CODE\"}")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" != "200" ]; then
        ERROR=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error', d.get('message', 'Unknown error')))" 2>/dev/null || echo "HTTP $HTTP_CODE")
        echo "MFA verification failed: $ERROR"
        exit 1
    fi

    ACCESS_TOKEN=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('accessToken', ''))" 2>/dev/null)
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: No access token received."
    echo "Raw response: $BODY"
    exit 1
fi

echo "Authenticated."

# Try to get server connection details from the API
echo "Fetching server info..."

# Try known API patterns for game server config
SERVER_RESPONSE=""
for ENDPOINT in \
    "https://api.swginfinity.com/api/v2/launcher/server-config" \
    "https://api.swginfinity.com/api/v2/game/config" \
    "https://api.swginfinity.com/api/v2/server/connection" \
    "https://api.swginfinity.com/api/v2/launcher/launch"; do

    RESP=$(curl -s -w "\n%{http_code}" "$ENDPOINT" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json")
    CODE=$(echo "$RESP" | tail -1)

    if [ "$CODE" = "200" ]; then
        SERVER_RESPONSE=$(echo "$RESP" | sed '$d')
        echo "Found server config at: $ENDPOINT"
        break
    fi
done

if [ -n "$SERVER_RESPONSE" ]; then
    LOGIN_HOST=$(echo "$SERVER_RESPONSE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
# Try common key patterns
for key in ['loginHost', 'loginServerAddress', 'host', 'server', 'address', 'gameServer']:
    if key in d:
        print(d[key])
        sys.exit(0)
# Recurse one level
for v in d.values():
    if isinstance(v, dict):
        for key in ['loginHost', 'loginServerAddress', 'host', 'server', 'address']:
            if key in v:
                print(v[key])
                sys.exit(0)
print('')
" 2>/dev/null)

    LOGIN_PORT=$(echo "$SERVER_RESPONSE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for key in ['loginPort', 'loginServerPort', 'port']:
    if key in d:
        print(d[key])
        sys.exit(0)
for v in d.values():
    if isinstance(v, dict):
        for key in ['loginPort', 'loginServerPort', 'port']:
            if key in v:
                print(v[key])
                sys.exit(0)
print('')
" 2>/dev/null)
fi

# Fall back to defaults if API didn't return server info
LOGIN_HOST="${LOGIN_HOST:-game.swginfinity.com}"
LOGIN_PORT="${LOGIN_PORT:-44453}"

echo ""
echo "Server: $LOGIN_HOST:$LOGIN_PORT"

# Write the login config
LOGIN_CFG="$GAME_DIR/swgemu_login.cfg"
cat > "$LOGIN_CFG" << EOF
[ClientGame]
loginServerAddress0=$LOGIN_HOST
loginServerPort0=$LOGIN_PORT
autoConnectToLoginServer=true
EOF

echo "Wrote: $LOGIN_CFG"

# Write swgemu.cfg (master config with include chain)
# Note: swgemu_preload.cfg is NOT included — its [SharedFile] section
# replaces swgemu_live.cfg's, killing all patch .tre entries.
# Base .tre entries (bottom.tre, infinity_xmas.tre) go directly in swgemu_live.cfg.
SWGEMU_CFG="$GAME_DIR/swgemu.cfg"
cat > "$SWGEMU_CFG" << 'EOF'
.include "options.cfg"
.include "swgemu_live.cfg"
.include "swgemu_login.cfg"
.include "user_infinity.cfg"
.include "user.cfg"
EOF
echo "Wrote: $SWGEMU_CFG"

# Patch swgemu_live.cfg with base .tre entries if missing.
# The SWG config parser replaces duplicate [SharedFile] sections instead of
# merging them, so all searchTree entries must be in one [SharedFile] block.
LIVE_CFG="$GAME_DIR/swgemu_live.cfg"
if [ -f "$LIVE_CFG" ]; then
    PATCHED=false
    if ! grep -q 'bottom\.tre' "$LIVE_CFG"; then
        sed -i '' '/searchTree_00_30=/a\
    searchTree_00_01=infinity_xmas.tre\
    searchTree_00_00=bottom.tre
' "$LIVE_CFG"
        PATCHED=true
    fi
    if [ "$PATCHED" = true ]; then
        echo "Patched: $LIVE_CFG (added base .tre entries)"
    fi
fi

echo ""
echo "Ready to launch. Open SWG Infinity.app or run Test Run in Configure."
