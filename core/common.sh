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
            battery|ac|status|test|recover)
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

# --- DE user detection -------------------------------------------------------
detect_display_user() {
    # Try multiple methods to find the active display user
    local user=""
    
    # Method 1: Check loginctl for active sessions
    if command -v loginctl &>/dev/null; then
        user=$(loginctl list-sessions --no-legend | grep -E '(seat0|tty)' | head -1 | awk '{print $3}')
        if [[ -n "$user" ]]; then
            echo "$user"
            return 0
        fi
    fi
    
    # Method 2: Check DBUS_SESSION_BUS_ADDRESS owner
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        user=$(stat -c %U "/run/user/$(id -u)/bus" 2>/dev/null)
        if [[ -n "$user" ]]; then
            echo "$user"
            return 0
        fi
    fi
    
    # Method 3: Check who command
    user=$(who | grep -E '(:0|tty|wayland)' | head -1 | awk '{print $1}')
    if [[ -n "$user" ]]; then
        echo "$user"
        return 0
    fi
    
    # Method 4: Check $USER if we're already in user context
    if [[ "$EUID" -ne 0 ]] && [[ -n "${USER:-}" ]]; then
        echo "$USER"
        return 0
    fi
    
    # Method 5: Get user from $SUDO_USER if running under sudo
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
        return 0
    fi
    
    echo ""
    return 1
}

# --- Run command as display user ---------------------------------------------
run_as_display_user() {
    local display_user="$1"
    shift
    
    if [[ "$EUID" -eq 0 ]]; then
        # Running as root, need to sudo to user with proper environment
        # Get environment from user's desktop process (plasmashell or gnome-shell)
        local desktop_pid
        desktop_pid=$(pgrep -u "$display_user" -x "plasmashell|gnome-shell" | head -1)
        
        if [[ -n "$desktop_pid" ]] && [[ -r "/proc/$desktop_pid/environ" ]]; then
            # Extract environment variables from the desktop process
            local env_display env_wayland env_dbus env_xdg
            env_display=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^DISPLAY=" | cut -d= -f2-)
            env_wayland=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^WAYLAND_DISPLAY=" | cut -d= -f2-)
            env_dbus=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^DBUS_SESSION_BUS_ADDRESS=" | cut -d= -f2-)
            env_xdg=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^XDG_RUNTIME_DIR=" | cut -d= -f2-)
            
            # Run command with desktop environment
            sudo -u "$display_user" \
                DISPLAY="${env_display:-$DISPLAY}" \
                WAYLAND_DISPLAY="${env_wayland:-$WAYLAND_DISPLAY}" \
                DBUS_SESSION_BUS_ADDRESS="${env_dbus}" \
                XDG_RUNTIME_DIR="${env_xdg}" \
                "$@"
        else
            # Fallback: basic sudo without special environment
            sudo -u "$display_user" "$@"
        fi
    else
        # Already running as user
        "$@"
    fi
}
