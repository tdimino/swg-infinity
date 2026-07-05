#!/usr/bin/env bash
# Config file, TRE file, system, and plist auditing.

swg_audit_system() {
    swg_log "=== SWG Infinity Audit ==="
    swg_log "Date: $(date)"
    swg_log "macOS: $(sw_vers -productVersion) ($(uname -m))"
    swg_log "Chip: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
    swg_log "RAM: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1073741824}' || echo "unknown")"

    local wine_ver
    wine_ver=$("$WINE" --version 2>/dev/null || echo "unknown")
    swg_log "Wine: $wine_ver"
    swg_log "Wrapper: $WRAPPER"

    swg_log "--- GPU ---"
    local gpu_info
    gpu_info=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|VRAM|Metal' | head -3 | sed 's/^[[:space:]]*/  /' || true)
    if [ -n "$gpu_info" ]; then
        echo "$gpu_info" | while IFS= read -r gl; do swg_log "$gl"; done
    else
        swg_log "  GPU info unavailable"
    fi

    # Display environment snapshot — mode-change failures depend on the mode
    # list macOS exposes, which shifts with scaling/refresh/monitor changes.
    swg_log "--- Displays ---"
    local disp_info
    disp_info=$(system_profiler SPDisplaysDataType 2>/dev/null \
        | grep -E 'Display Type|Resolution|UI Looks like|Refresh|Main Display|Connection Type|Mirror' \
        | sed 's/^[[:space:]]*/  /' || true)
    if [ -n "$disp_info" ]; then
        echo "$disp_info" | while IFS= read -r dl; do swg_log "$dl"; done
    else
        swg_log "  display info unavailable"
    fi
}

swg_audit_configs() {
    swg_log "--- Config file audit ---"
    local -a required=(swgemu.cfg swgemu_login.cfg swgemu_live.cfg options.cfg)
    local -a optional=(swgemu_preload.cfg user.cfg user_infinity.cfg)
    local fatal=0

    for cfg in "${required[@]}"; do
        if [ -f "$GAME_DIR/$cfg" ]; then
            swg_log "  [OK]    $cfg ($(wc -l < "$GAME_DIR/$cfg" | tr -d ' ') lines, $(stat -f%z "$GAME_DIR/$cfg") bytes)"
        else
            swg_log "  [MISS:FATAL]  $cfg"
            fatal=$((fatal + 1))
        fi
    done
    for cfg in "${optional[@]}"; do
        if [ -f "$GAME_DIR/$cfg" ]; then
            swg_log "  [OK]    $cfg ($(wc -l < "$GAME_DIR/$cfg" | tr -d ' ') lines, $(stat -f%z "$GAME_DIR/$cfg") bytes)"
        else
            swg_log "  [MISS:OK]  $cfg — optional"
        fi
    done

    swg_log "--- Config content validation ---"
    if [ -f "$GAME_DIR/swgemu_login.cfg" ]; then
        if grep -q 'loginServerAddress' "$GAME_DIR/swgemu_login.cfg"; then
            swg_log "  swgemu_login.cfg: loginServerAddress present"
        else
            swg_log "  swgemu_login.cfg: WARNING — no loginServerAddress"
            fatal=$((fatal + 1))
        fi
    fi
    if [ -f "$GAME_DIR/swgemu.cfg" ]; then
        while IFS= read -r inc_line; do
            local inc_file
            inc_file=$(echo "$inc_line" | grep -o '"[^"]*"' | tr -d '"' || true)
            # user_autologin.cfg is written just-in-time at launch and deleted
            # after — absent by design outside a live session
            [ "$inc_file" = "user_autologin.cfg" ] && continue
            if [ -n "$inc_file" ] && [ ! -f "$GAME_DIR/$inc_file" ]; then
                swg_log "  swgemu.cfg: WARNING — .include \"$inc_file\" but file missing"
            fi
        done < <(grep '\.include' "$GAME_DIR/swgemu.cfg" 2>/dev/null)
    fi

    return "$fatal"
}

swg_audit_tres() {
    swg_log "--- TRE file audit ---"
    local tre_count=0 tre_missing=0

    for tre in "$GAME_DIR"/*.tre; do
        [ -f "$tre" ] || continue
        tre_count=$((tre_count + 1))
    done
    swg_log "  $tre_count .tre files present"

    swg_check_tre() {
        local src="$1" tre_name="$2"
        if [ -f "$GAME_DIR/$tre_name" ]; then
            local actual
            actual=$(ls -1 "$GAME_DIR" 2>/dev/null | grep -ix "$tre_name" | head -1)
            if [ -n "$actual" ] && [ "$actual" != "$tre_name" ]; then
                swg_log "  [CASE]  $src: config=$tre_name disk=$actual"
            fi
        else
            swg_log "  [MISS]  $src: $tre_name — WILL CRASH"
            tre_missing=$((tre_missing + 1))
        fi
    }

    if [ -f "$GAME_DIR/swgemu_live.cfg" ]; then
        while IFS= read -r line; do
            local tre_name
            tre_name=$(echo "$line" | grep -o '[^=]*\.tre' || true)
            [ -n "$tre_name" ] && swg_check_tre "live" "$tre_name"
        done < "$GAME_DIR/swgemu_live.cfg"
    fi

    if [ "$tre_missing" -gt 0 ]; then
        swg_log "WARNING: $tre_missing .tre file(s) referenced in config but missing"
    fi

    return "$tre_missing"
}

swg_audit_plist() {
    swg_log "--- Plist flags ---"
    if [ -f "$PLIST" ]; then
        for key in DXMT DXVK D9VK WINEESYNC WINEMSYNC "Debug Mode"; do
            local val
            val=$(swg_plist_read "$key" || echo "unset")
            swg_log "  $key = $val"
        done
    fi
}

swg_audit_all() {
    swg_require "$GAME_DIR" "Game directory"
    swg_require "$WINE" "Wine binary"

    swg_audit_system
    local cfg_err=0 tre_err=0
    swg_audit_configs || cfg_err=$?
    swg_audit_tres || tre_err=$?
    swg_audit_plist

    local total=$((cfg_err + tre_err))
    if [ "$total" -gt 0 ]; then
        swg_log "Audit found $total issue(s)"
    else
        swg_log "Audit clean"
    fi
    return "$total"
}

swg_cmd_audit() {
    swg_audit_all
}
