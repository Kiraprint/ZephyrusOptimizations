#!/usr/bin/env bash
# =============================================================================
# display.sh — Display refresh rate management for KDE Plasma (Wayland/X11)
#
# Test independently:
#   ./display.sh status
#   ./display.sh battery
#   ./display.sh ac
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../core/common.sh"
LOG_PREFIX="[display-kde]"

# Panel: Samsung ATNA60DL01-0 OLED 2560x1600 with VRR 48-240Hz
BATTERY_REFRESH=60
AC_REFRESH=240

get_current_mode() {
    # Use kscreen-doctor to get current mode
    kscreen-doctor -o 2>/dev/null | grep -A 5 "Output:" | grep "Mode:" | head -1
}

list_available_modes() {
    # List all available modes for connected displays
    kscreen-doctor -o 2>/dev/null | grep -E "(Output:|Mode:)" | head -20
}

show_status() {
    echo "=== Display Status (KDE) ==="
    echo ""
    
    echo "Panel: Samsung ATNA60DL01-0 OLED"
    echo "Native: 2560x1600 @ 240Hz (VRR 48-240Hz)"
    echo ""
    
    # Check DRM modes
    echo "DRM connector:"
    for drm in /sys/class/drm/card*-eDP*; do
        if [[ -e "$drm" ]]; then
            local name=$(basename "$drm")
            local status=$(cat "$drm/status" 2>/dev/null || echo "?")
            echo "  $name: $status"
        fi
    done
    echo ""
    
    # Check KDE/kscreen
    echo "KDE/kscreen modes:"
    if command -v kscreen-doctor &>/dev/null; then
        local modes
        modes=$(list_available_modes 2>/dev/null)
        if [[ -n "$modes" ]]; then
            echo "$modes" | sed 's/^/  /'
        else
            echo "  (Could not query kscreen-doctor - are you in a KDE session?)"
        fi
    else
        echo "  (kscreen-doctor not found - KDE Plasma not installed?)"
    fi
    echo ""
    
    # VRR status - check both sysfs and kscreen-doctor
    local vrr_status="not detected"
    
    # Check kscreen-doctor output
    if command -v kscreen-doctor &>/dev/null; then
        local kscreen_vrr
        # Clean up ANSI codes and extract just the value after "Vrr:"
        kscreen_vrr=$(kscreen-doctor -o 2>/dev/null | grep -i "Vrr:" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/.*Vrr:[[:space:]]*//' | tr -d '\t')
        if [[ -n "$kscreen_vrr" ]] && [[ "$kscreen_vrr" != "incapable" ]]; then
            vrr_status="$kscreen_vrr (48-240Hz adaptive)"
        fi
    fi
    
    # Fallback: check sysfs
    if [[ "$vrr_status" == "not detected" ]]; then
        for vrr_file in /sys/class/drm/card*/card*-eDP*/vrr_capable; do
            if [[ -f "$vrr_file" ]] && [[ "$(cat "$vrr_file" 2>/dev/null)" == "1" ]]; then
                vrr_status="capable"
                break
            fi
        done
    fi
    
    echo "VRR: $vrr_status"
}

set_refresh_rate() {
    local target_rate="$1"
    log "Setting display refresh rate to ${target_rate}Hz..."
    
    # Detect logged-in user
    local display_user=""
    if [[ "$EUID" -eq 0 ]]; then
        display_user=$(detect_display_user)
        if [[ -z "$display_user" ]]; then
            log "  [skip] Cannot detect display user (no active session)"
            return 0
        fi
    else
        display_user="$USER"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set refresh rate to ${target_rate}Hz"
        return 0
    fi
    
    # Check if kscreen-doctor is available
    if ! command -v kscreen-doctor &>/dev/null; then
        log "  [skip] kscreen-doctor not found (KDE Plasma not installed?)"
        return 0
    fi
    
    # Get environment from user's desktop process
    local desktop_pid
    desktop_pid=$(pgrep -u "$display_user" -x "plasmashell" | head -1)
    
    if [[ -z "$desktop_pid" ]] || [[ ! -r "/proc/$desktop_pid/environ" ]]; then
        log "  [skip] Cannot access desktop session environment"
        return 0
    fi
    
    # Extract display environment
    local env_display env_wayland env_xdg env_dbus
    env_display=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^DISPLAY=" | cut -d= -f2-)
    env_wayland=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^WAYLAND_DISPLAY=" | cut -d= -f2-)
    env_xdg=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^XDG_RUNTIME_DIR=" | cut -d= -f2-)
    env_dbus=$(tr '\0' '\n' < "/proc/$desktop_pid/environ" | grep "^DBUS_SESSION_BUS_ADDRESS=" | cut -d= -f2-)
    
    # Get kscreen output
    local kscreen_output
    if [[ "$EUID" -eq 0 ]]; then
        kscreen_output=$(sudo -u "$display_user" \
            DISPLAY="${env_display}" \
            WAYLAND_DISPLAY="${env_wayland}" \
            XDG_RUNTIME_DIR="${env_xdg}" \
            kscreen-doctor -o 2>/dev/null)
    else
        kscreen_output=$(kscreen-doctor -o 2>/dev/null)
    fi
    
    # Strip ANSI color codes
    kscreen_output=$(echo "$kscreen_output" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Temporarily disable pipefail for grep pipelines
    set +o pipefail
    
    local output_id
    output_id=$(echo "$kscreen_output" | grep "Output:" | grep -oP 'Output: \K\d+' | head -1)
    
    if [[ -z "$output_id" ]]; then
        set -o pipefail
        log "  [warn] Could not detect output ID"
        return 1
    fi
    
    # Find mode for target refresh rate
    local modes_output
    modes_output=$(echo "$kscreen_output" | grep "Modes:")
    
    local mode_num
    mode_num=$(echo "$modes_output" | grep -oP '\d+:2560x1600@'$target_rate'\.?\d*' | head -1 | cut -d: -f1)
    
    set -o pipefail
    
    if [[ -z "$mode_num" ]]; then
        log "  [warn] Could not find mode for ${target_rate}Hz"
        log "  [info] Available modes:"
        echo "$modes_output" | grep -oP '\d+:2560x1600@\d+' | sed 's/^/         /' | head -5
        return 1
    fi
    
    # Set the mode
    if [[ "$EUID" -eq 0 ]]; then
        sudo -u "$display_user" \
            DISPLAY="${env_display}" \
            WAYLAND_DISPLAY="${env_wayland}" \
            XDG_RUNTIME_DIR="${env_xdg}" \
            kscreen-doctor output.${output_id}.mode.${mode_num} 2>/dev/null
    else
        kscreen-doctor output.${output_id}.mode.${mode_num} 2>/dev/null
    fi
    
    if [[ $? -eq 0 ]]; then
        log "  [ok] Refresh rate set to ${target_rate}Hz (mode ${mode_num})"
        return 0
    else
        log "  [warn] Failed to set refresh rate"
        log "  [info] Use KDE System Settings → Display Configuration"
        return 1
    fi
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
            echo "  battery    Set 60Hz (VRR adapts 48-60Hz)"
            echo "  ac         Set 240Hz (full panel speed)"
            echo "  status     Show current display settings"
            exit 1
            ;;
    esac
}

main "$@"
