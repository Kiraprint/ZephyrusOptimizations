#!/usr/bin/env bash
# =============================================================================
# display.sh — Display refresh rate management for Wayland/GNOME
#
# Test independently:
#   ./display.sh status
#   ./display.sh battery
#   ./display.sh ac
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[display]"

# Panel: Samsung ATNA60DL01-0 OLED 2560x1600 with VRR 48-240Hz
BATTERY_REFRESH=60
AC_REFRESH=240

get_current_mode() {
    # Get current mode from Mutter D-Bus API
    gdbus call --session \
        --dest org.gnome.Mutter.DisplayConfig \
        --object-path /org/gnome/Mutter/DisplayConfig \
        --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | \
        grep -oP "'[0-9]+x[0-9]+@[0-9.]+[^']*'" | head -1 | tr -d "'"
}

list_available_modes() {
    gdbus call --session \
        --dest org.gnome.Mutter.DisplayConfig \
        --object-path /org/gnome/Mutter/DisplayConfig \
        --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | \
        grep -oP "'2560x1600@[0-9.]+[^']*'" | tr -d "'" | sort -t@ -k2 -rn | uniq
}

show_status() {
    echo "=== Display Status ==="
    echo ""
    
    echo "Panel: Samsung ATNA60DL01-0 OLED"
    echo "Native: 2560x1600 @ 240Hz (VRR 48-240Hz)"
    echo ""
    
    # Check DRM modes
    echo "DRM connector:"
    for drm in /sys/class/drm/card*-eDP*; do
        local name=$(basename "$drm")
        local status=$(cat "$drm/status" 2>/dev/null || echo "?")
        echo "  $name: $status"
    done
    echo ""
    
    # Check Mutter/GNOME
    echo "GNOME/Mutter modes (Wayland):"
    local modes
    modes=$(list_available_modes 2>/dev/null)
    if [[ -n "$modes" ]]; then
        echo "$modes" | head -10 | sed 's/^/  /'
        echo ""
        
        # Try to find current mode
        echo "Current mode (from xrandr, may show 60Hz on Wayland):"
        xrandr --current 2>/dev/null | grep -E "^\s+[0-9]+x[0-9]+.*\*" | head -1 | sed 's/^/  /'
    else
        echo "  (Could not query Mutter - are you in a GNOME session?)"
    fi
    echo ""
    
    # VRR status
    local vrr_setting
    vrr_setting=$(gsettings get org.gnome.mutter experimental-features 2>/dev/null)
    if [[ "$vrr_setting" == *"variable-refresh-rate"* ]]; then
        echo "VRR: ENABLED (48-240Hz adaptive)"
    else
        echo "VRR: disabled"
        echo "  To enable: gsettings set org.gnome.mutter experimental-features \"['variable-refresh-rate']\""
    fi
}

set_refresh_rate() {
    local target_rate="$1"
    log "Setting display refresh rate to ${target_rate}Hz..."
    
    # Check if we're in a graphical session
    if [[ -z "$DISPLAY" ]] && [[ -z "$WAYLAND_DISPLAY" ]]; then
        log "  [skip] No display session detected"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set refresh rate to ${target_rate}Hz"
        return 0
    fi
    
    # Use our Python script that properly interfaces with Mutter D-Bus API
    local script_path="$SCRIPT_DIR/set-refresh-rate.py"
    if [[ -x "$script_path" ]]; then
        local output
        output=$("$script_path" "$target_rate" 2>&1)
        if [[ $? -eq 0 ]]; then
            log "  [ok] $output"
            return 0
        else
            log "  [warn] $output"
        fi
    fi
    
    # Fallback info
    log "  [info] Could not change refresh rate programmatically"
    log "  [info] Use GNOME Settings → Displays, or the Quick Settings extension"
}

apply_battery() {
    log "=== Applying battery display settings ==="
    
    set_refresh_rate $BATTERY_REFRESH
    
    log ""
    log "Battery display settings applied"
    log "Note: With VRR enabled, your OLED will:"
    log "  - Drop to 48Hz when idle (max power savings)"
    log "  - Ramp up to ${BATTERY_REFRESH}Hz during activity"
}

apply_ac() {
    log "=== Applying AC display settings ==="
    
    set_refresh_rate $AC_REFRESH
    
    log ""
    log "AC display settings applied (${AC_REFRESH}Hz)"
}

main() {
    local mode="${1:-status}"
    
    # Handle --dry-run flag
    if [[ "${2:-}" == "--dry-run" ]]; then
        DRY_RUN="true"
    fi
    
    case "$mode" in
        battery)  apply_battery ;;
        ac)       apply_ac ;;
        status)   show_status ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "  battery    Set 60Hz (VRR adapts 48-60Hz)"
            echo "  ac         Set 240Hz (full panel speed)"
            echo "  status     Show current display settings"
            exit 1
            ;;
    esac
}

main "$@"
