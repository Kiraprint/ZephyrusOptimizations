#!/usr/bin/env bash
# =============================================================================
# common.sh — Shared helpers for power optimization modules
# Source this file in each module: source "$(dirname "$0")/common.sh"
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
WIFI_IFACE="${WIFI_IFACE:-wlan0}"
AC_SUPPLY="${AC_SUPPLY:-/sys/class/power_supply/ACAD/online}"
DRY_RUN="${DRY_RUN:-false}"
LOG_PREFIX="${LOG_PREFIX:-[power]}"

# --- Logging -----------------------------------------------------------------
log() {
    echo "$LOG_PREFIX $*"
}

warn() {
    echo "$LOG_PREFIX WARNING: $*" >&2
}

# --- Safe sysfs write --------------------------------------------------------
sysfs_write() {
    local path="$1"
    local value="$2"
    local description="${3:-$path}"

    if [[ ! -e "$path" ]]; then
        warn "Path does not exist, skipping: $path"
        return 0
    fi

    local current
    current=$(cat "$path" 2>/dev/null) || current="(unreadable)"

    # Handle sysfs files that show options with active one in [brackets]
    if [[ "$current" == *"[$value]"* ]] || [[ "$current" == "$value" ]]; then
        log "  [skip] $description — already '$value'"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] $description: '$current' → '$value'"
    else
        if echo "$value" | tee "$path" > /dev/null 2>&1; then
            log "  [ok] $description: '$current' → '$value'"
        else
            warn "Failed to write '$value' to $path (was '$current')"
            return 1
        fi
    fi
}

# --- Power source detection --------------------------------------------------
detect_power_source() {
    if [[ -f "$AC_SUPPLY" ]]; then
        local ac_online
        ac_online=$(cat "$AC_SUPPLY" 2>/dev/null)
        if [[ "$ac_online" == "1" ]]; then
            echo "ac"
        else
            echo "battery"
        fi
    else
        warn "Cannot detect power source at $AC_SUPPLY"
        echo "unknown"
    fi
}

# --- Root check --------------------------------------------------------------
require_root() {
    if [[ "$EUID" -ne 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo "Error: This operation requires root. Use: sudo $0" >&2
        exit 1
    fi
}

# --- Module argument parser --------------------------------------------------
parse_module_args() {
    local mode=""
    for arg in "$@"; do
        case "$arg" in
            battery|ac|status|test)
                mode="$arg"
                ;;
            --dry-run)
                DRY_RUN="true"
                export DRY_RUN
                ;;
        esac
    done
    echo "$mode"
}
