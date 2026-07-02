#!/usr/bin/env bash
#
# Launch SWG Infinity via the Sikarugir Wine wrapper with correct CWD.
#
# Sikarugir uses Wine's start.exe which doesn't set the working directory
# to the game folder. SWG requires CWD = game directory because .tre file
# paths in swgemu_live.cfg are relative. This script bypasses start.exe
# and runs Wine directly with cd into the game directory.
#
# Usage:
#   ./launch.sh           # Launch the game
#   ./launch.sh --login   # Authenticate first, then launch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$HOME/Applications/Sikarugir/SWG Infinity.app"
WINE="$WRAPPER/Contents/SharedSupport/wine/bin/wine"
PREFIX="$WRAPPER/Contents/SharedSupport/prefix"
GAME_DIR="$PREFIX/drive_c/SWG Infinity"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/launch-$(date +%Y%m%d-%H%M%S).log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG_FILE"; }

log "=== SWG Infinity Launch Log ==="
log "Date: $(date)"
log "macOS: $(sw_vers -productVersion) ($(uname -m))"
log "Chip: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
log "RAM: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1073741824}')"

WINE_VER=$("$WINE" --version 2>/dev/null || echo "unknown")
log "Wine: $WINE_VER"
log "Wrapper: $WRAPPER"
log "Prefix: $PREFIX"
log "Game dir: $GAME_DIR"

if [ ! -d "$GAME_DIR" ]; then
    log "FATAL: Game directory not found: $GAME_DIR"
    exit 1
fi

if [ ! -f "$WINE" ]; then
    log "FATAL: Wine binary not found: $WINE"
    exit 1
fi

log "--- GPU ---"
GPU_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM|Metal' | head -3 | sed 's/^[[:space:]]*/  /' || true)
if [ -n "$GPU_INFO" ]; then
    echo "$GPU_INFO" | while IFS= read -r gl; do log "$gl"; done
else
    log "  GPU info unavailable"
fi

log "--- Config file audit ---"
REQUIRED_CFGS="swgemu.cfg swgemu_login.cfg swgemu_live.cfg options.cfg"
OPTIONAL_CFGS="swgemu_preload.cfg user.cfg user_infinity.cfg"
for cfg in $REQUIRED_CFGS; do
    if [ -f "$GAME_DIR/$cfg" ]; then
        log "  [OK]    $cfg ($(wc -l < "$GAME_DIR/$cfg" | tr -d ' ') lines, $(stat -f%z "$GAME_DIR/$cfg") bytes)"
    else
        log "  [MISS:FATAL]  $cfg — required, game will crash without it"
    fi
done
for cfg in $OPTIONAL_CFGS; do
    if [ -f "$GAME_DIR/$cfg" ]; then
        log "  [OK]    $cfg ($(wc -l < "$GAME_DIR/$cfg" | tr -d ' ') lines, $(stat -f%z "$GAME_DIR/$cfg") bytes)"
    else
        log "  [MISS:OK]  $cfg — optional user override"
    fi
done

log "--- Config content validation ---"
if [ -f "$GAME_DIR/swgemu_login.cfg" ]; then
    if grep -q 'loginServerAddress' "$GAME_DIR/swgemu_login.cfg"; then
        log "  swgemu_login.cfg: loginServerAddress present"
    else
        log "  swgemu_login.cfg: WARNING — no loginServerAddress found, will fail to connect"
    fi
fi
if [ -f "$GAME_DIR/swgemu_preload.cfg" ]; then
    if grep -q 'searchTree' "$GAME_DIR/swgemu_preload.cfg"; then
        log "  swgemu_preload.cfg: searchTree entries present"
    else
        log "  swgemu_preload.cfg: WARNING — no searchTree entries, base assets won't load"
    fi
fi
if [ -f "$GAME_DIR/swgemu.cfg" ]; then
    while IFS= read -r inc_line; do
        inc_file=$(echo "$inc_line" | grep -o '"[^"]*"' | tr -d '"' || true)
        if [ -n "$inc_file" ] && [ ! -f "$GAME_DIR/$inc_file" ]; then
            log "  swgemu.cfg: WARNING — .include \"$inc_file\" but file missing"
        fi
    done < <(grep '\.include' "$GAME_DIR/swgemu.cfg" 2>/dev/null)
fi

log "--- TRE file audit ---"
TRE_COUNT=0
TRE_MISSING=0
for tre in "$GAME_DIR"/*.tre; do
    [ -f "$tre" ] || continue
    TRE_COUNT=$((TRE_COUNT + 1))
done
log "  $TRE_COUNT .tre files present"

check_tre() {
    local src="$1" tre_name="$2"
    if [ -f "$GAME_DIR/$tre_name" ]; then
        actual=$(ls -1 "$GAME_DIR" 2>/dev/null | grep -ix "$tre_name" | head -1)
        if [ -n "$actual" ] && [ "$actual" != "$tre_name" ]; then
            log "  [CASE]  $src: config=$tre_name disk=$actual — works on case-insensitive APFS only"
        elif [ "$src" = "preload" ]; then
            log "  [OK]    $src: $tre_name ($(stat -f%z "$GAME_DIR/$tre_name") bytes)"
        fi
    else
        log "  [MISS]  $src: $tre_name — WILL CRASH"
        TRE_MISSING=$((TRE_MISSING + 1))
    fi
}

if [ -f "$GAME_DIR/swgemu_preload.cfg" ]; then
    while IFS= read -r line; do
        tre_name=$(echo "$line" | grep -o '[^=]*\.tre' || true)
        [ -n "$tre_name" ] && check_tre "preload" "$tre_name"
    done < "$GAME_DIR/swgemu_preload.cfg"
fi

if [ -f "$GAME_DIR/swgemu_live.cfg" ]; then
    while IFS= read -r line; do
        tre_name=$(echo "$line" | grep -o '[^=]*\.tre' || true)
        [ -n "$tre_name" ] && check_tre "live" "$tre_name"
    done < "$GAME_DIR/swgemu_live.cfg"
fi

if [ "$TRE_MISSING" -gt 0 ]; then
    log "WARNING: $TRE_MISSING .tre file(s) referenced in config but missing on disk"
fi

log "--- Plist flags ---"
PLIST="$WRAPPER/Contents/Info.plist"
if [ -f "$PLIST" ]; then
    for key in DXMT DXVK D9VK WINEESYNC WINEMSYNC "Debug Mode"; do
        val=$(/usr/libexec/PlistBuddy -c "Print ':$key'" "$PLIST" 2>/dev/null || echo "unset")
        log "  $key = $val"
    done
fi

log "--- Environment ---"
log "  WINEPREFIX=$PREFIX"
log "  WINEESYNC=1"
log "  WINEMSYNC=1"
log "  DYLD_FALLBACK_LIBRARY_PATH=$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wine/lib"

if [ "${1:-}" = "--login" ]; then
    log "--- Running login.sh ---"
    if [ -f "$SCRIPT_DIR/login.sh" ]; then
        set +e
        "$SCRIPT_DIR/login.sh" "$GAME_DIR" 2>&1 | tee -a "$LOG_FILE"
        LOGIN_EXIT=${PIPESTATUS[0]}
        set -e
        if [ "$LOGIN_EXIT" -ne 0 ]; then
            log "FATAL: login.sh failed with exit code $LOGIN_EXIT"
            exit 1
        fi
        log "--- Login complete ---"
    else
        log "FATAL: login.sh not found in $SCRIPT_DIR"
        exit 1
    fi
fi

export WINEPREFIX="$PREFIX"
export WINEESYNC=1
export WINEMSYNC=1
export DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wine/lib"

log "--- Launching swgemu.exe ---"
log "CWD: $GAME_DIR"
cd "$GAME_DIR"

LAUNCH_MARKER="$LOG_DIR/.launch-marker-$$"
touch "$LAUNCH_MARKER"
trap 'rm -f "$LAUNCH_MARKER"' EXIT
LAUNCH_START=$(date +%s)
set +e
"$WINE" swgemu.exe 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e
LAUNCH_END=$(date +%s)
ELAPSED=$((LAUNCH_END - LAUNCH_START))

log "--- Process exited ---"
log "Exit code: $EXIT_CODE"
log "Runtime: ${ELAPSED}s"

if [ "$EXIT_CODE" -ne 0 ]; then
    case "$EXIT_CODE" in
        1)   SIG_NAME="general error" ;;
        134) SIG_NAME="SIGABRT (abort)" ;;
        136) SIG_NAME="SIGFPE (arithmetic)" ;;
        139) SIG_NAME="SIGSEGV (segfault)" ;;
        143) SIG_NAME="SIGTERM (terminated)" ;;
        *)   SIG_NAME="unknown" ;;
    esac
    log "CRASH: Wine exited with code $EXIT_CODE ($SIG_NAME) after ${ELAPSED}s"
    log "Full log: $LOG_FILE"

    CRASH_LOG=$(find "$PREFIX" -name "*.mdmp" -newer "$LAUNCH_MARKER" 2>/dev/null | head -5)
    if [ -n "$CRASH_LOG" ]; then
        log "Crash dumps found:"
        echo "$CRASH_LOG" | while read -r f; do log "  $f"; done
    fi

    CRASH_TXT=$(find "$PREFIX" -name "*.txt" -path "*swgemu*" -newer "$LAUNCH_MARKER" 2>/dev/null | head -5)
    if [ -n "$CRASH_TXT" ]; then
        log "Crash text reports:"
        echo "$CRASH_TXT" | while read -r f; do
            log "  $f"
            log "  --- contents ---"
            head -50 "$f" | tee -a "$LOG_FILE"
        done
    fi
fi

rm -f "$LAUNCH_MARKER"
log "Log saved: $LOG_FILE"
