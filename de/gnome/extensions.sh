#!/usr/bin/env bash
# =============================================================================
# extensions.sh — GNOME Shell extension management
#
# Test independently:
#   ./extensions.sh status
#   ./extensions.sh battery
#   ./extensions.sh ac
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../core/common.sh"
LOG_PREFIX="[gnome-extensions]"

# Extensions to disable on battery for power savings
BATTERY_DISABLE_EXTENSIONS=(
    "blur-my-shell@aunetx"
)

# Toggle GNOME Shell extension
toggle_extension() {
    local extension_id="$1"
    local action="$2"  # "enable" or "disable"
    
    # Detect logged-in user
    local display_user
    display_user=$(who | grep -E '(:0|tty)' | head -1 | awk '{print $1}')
    
    if [[ -z "$display_user" ]]; then
        log "  [skip] Cannot detect display user"
        return 0
    fi
    
    # Get user's D-Bus session address
    local dbus_addr
    dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$(pgrep -u "$display_user" gnome-shell | head -1)/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2-)
    
    if [[ -z "$dbus_addr" ]]; then
        log "  [skip] Cannot detect D-Bus session for $display_user"
        return 0
    fi
    
    # Check if extension is installed
    if ! sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions list 2>/dev/null | grep -q "^${extension_id}$"; then
        log "  [skip] Extension $extension_id not installed"
        return 0
    fi
    
    local current_state
    current_state=$(sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions info "$extension_id" 2>/dev/null | grep -oP 'State:\s+\K\w+')
    
    local target_state="ENABLED"
    [[ "$action" == "disable" ]] && target_state="DISABLED"
    
    if [[ "$current_state" == "$target_state" ]]; then
        log "  [skip] $extension_id already ${action}d"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would $action $extension_id"
        return 0
    fi
    
    if sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions "$action" "$extension_id" 2>/dev/null; then
        log "  [ok] $extension_id → ${action}d"
    else
        warn "Failed to $action $extension_id"
    fi
}

show_status() {
    echo "=== GNOME Extensions Status ==="
    
    # Detect logged-in user
    local display_user
    display_user=$(who | grep -E '(:0|tty)' | head -1 | awk '{print $1}')
    
    if [[ -z "$display_user" ]]; then
        echo "Cannot detect display user (no active GNOME session)"
        return 1
    fi
    
    # Get user's D-Bus session address
    local dbus_addr
    dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$(pgrep -u "$display_user" gnome-shell | head -1)/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2-)
    
    if [[ -z "$dbus_addr" ]]; then
        echo "Cannot detect D-Bus session for $display_user"
        return 1
    fi
    
    echo "Power-managed extensions:"
    for ext in "${BATTERY_DISABLE_EXTENSIONS[@]}"; do
        local state
        state=$(sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions info "$ext" 2>/dev/null | grep -oP 'State:\s+\K\w+' || echo "NOT_INSTALLED")
        echo "  $ext: $state"
    done
}

apply_battery() {
    log "=== Applying battery extension settings ==="
    
    for ext in "${BATTERY_DISABLE_EXTENSIONS[@]}"; do
        toggle_extension "$ext" "disable"
    done
    
    log ""
    log "Battery extension settings applied (heavy effects disabled)"
}

apply_ac() {
    log "=== Applying AC extension settings ==="
    
    for ext in "${BATTERY_DISABLE_EXTENSIONS[@]}"; do
        toggle_extension "$ext" "enable"
    done
    
    log ""
    log "AC extension settings applied (visual effects enabled)"
}

main() {
    local mode
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && DRY_RUN="true" && export DRY_RUN && break
    done
    mode=$(parse_module_args "$@")
    
    case "$mode" in
        battery)  apply_battery ;;
        ac)       apply_ac ;;
        status)   show_status ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "  battery    Disable heavy extensions for battery savings"
            echo "  ac         Enable full visual effects"
            echo "  status     Show current extension states"
            exit 1
            ;;
    esac
}

main "$@"
