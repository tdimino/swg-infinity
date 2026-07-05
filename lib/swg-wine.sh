#!/usr/bin/env bash
# Wine environment, invocation, and crash diagnostics.

swg_setup_wine_env() {
    export WINEPREFIX="$PREFIX"
    export WINEESYNC=1
    export WINEMSYNC=1
    export DYLD_FALLBACK_LIBRARY_PATH="$WRAPPER/Contents/Frameworks:$WRAPPER/Contents/SharedSupport/wine/lib"
    # Cap the client's startup memory preallocation. Uncapped, it reserves 75%
    # of the RAM Wine reports (~2.6 GB) as one contiguous block, which cannot
    # fit in the fragmented 32-bit address space under wow64.
    export SWGCLIENT_MEMORY_SIZE_MB="${SWG_MEMORY_MB:-1024}"
    export WINE_LARGE_ADDRESS_AWARE=1
}

swg_run_exe() {
    local exe="$1"; shift
    swg_require "$WINE" "Wine binary"
    swg_require "$GAME_DIR" "Game directory"
    swg_setup_wine_env

    local log_dir="$SWG_ROOT/logs"
    mkdir -p "$log_dir"
    SWG_LOG_FILE="$log_dir/launch-$(date +%Y%m%d-%H%M%S).log"

    local marker="$log_dir/.launch-marker-$$"
    touch "$marker"
    trap 'rm -f "$marker"' EXIT

    swg_log "--- Launching $exe ---"
    swg_log "CWD: $GAME_DIR"

    local start_time exit_code
    start_time=$(date +%s)
    set +e
    (cd "$GAME_DIR" && "$WINE" "$exe" "$@") 2>&1 | tee -a "$SWG_LOG_FILE"
    exit_code=${PIPESTATUS[0]}
    set -e
    local elapsed=$(( $(date +%s) - start_time ))

    swg_log "--- Process exited ---"
    swg_log "Exit code: $exit_code"
    swg_log "Runtime: ${elapsed}s"

    if [ "$exit_code" -ne 0 ]; then
        swg_report_crash "$exit_code" "$elapsed" "$marker"
    fi

    rm -f "$marker"
    trap - EXIT
    swg_log "Log saved: $SWG_LOG_FILE"
    return "$exit_code"
}

swg_report_crash() {
    local exit_code="$1" elapsed="$2" marker="$3"
    local sig_name
    case "$exit_code" in
        1)   sig_name="general error" ;;
        134) sig_name="SIGABRT (abort)" ;;
        136) sig_name="SIGFPE (arithmetic)" ;;
        139) sig_name="SIGSEGV (segfault)" ;;
        143) sig_name="SIGTERM (terminated)" ;;
        *)   sig_name="unknown" ;;
    esac
    swg_log "CRASH: Wine exited with code $exit_code ($sig_name) after ${elapsed}s"

    local dumps
    dumps=$(find "$PREFIX" -name "*.mdmp" -newer "$marker" 2>/dev/null | head -5)
    if [ -n "$dumps" ]; then
        swg_log "Crash dumps found:"
        echo "$dumps" | while read -r f; do swg_log "  $f"; done
    fi

    local crash_txt
    crash_txt=$(find "$PREFIX" -name "*.txt" -path "*swgemu*" -newer "$marker" 2>/dev/null | head -5)
    if [ -n "$crash_txt" ]; then
        swg_log "Crash text reports:"
        echo "$crash_txt" | while read -r f; do
            swg_log "  $f"
            head -50 "$f" | tee -a "$SWG_LOG_FILE"
        done
    fi
}

swg_cmd_launch() {
    local do_login=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --login) do_login=true; shift ;;
            --help|-h) echo "Usage: swg launch [--login]"; return 0 ;;
            *) echo "Unknown option: $1"; return 1 ;;
        esac
    done

    if [ "$do_login" = true ]; then
        swg_cmd_login
    fi

    if ! swg_audit_all; then
        swg_die "Launch aborted — fix the issues above first"
    fi

    # The client refuses to load its .tre archives unless launched with the
    # launcher's config args (extracted from infinity-launcher.exe) — without
    # them TreeFile registers nothing and the first asset lookup is fatal.
    swg_run_exe swgemu.exe -- \
        -s Station subscriptionFeatures=1 gameFeatures=65535 \
        -s SwgClient allowMultipleInstances=true
}

swg_cmd_shell() {
    swg_require "$WINE" "Wine binary"
    swg_setup_wine_env
    swg_log "Entering Wine shell (WINEPREFIX=$PREFIX)"
    swg_log "Type 'exit' to return."
    cd "$GAME_DIR" 2>/dev/null || cd "$PREFIX"
    exec "${SHELL:-/bin/bash}"
}

swg_cmd_kill() {
    swg_require "$WINESERVER" "wineserver"
    swg_setup_wine_env
    "$WINESERVER" -k
    swg_log "wineserver killed"
}
