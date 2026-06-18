#!/usr/bin/env bash
# =============================================================================
# usb.sh — USB autosuspend management (HID-aware)
#
# Test independently:
#   sudo ./usb.sh battery --dry-run
#   sudo ./usb.sh ac --dry-run
#   ./usb.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[usb]"

usb_autosuspend() {
    local timeout="$1"  # seconds, or -1 to disable
    local description="USB autosuspend → ${timeout}s"
    [[ "$timeout" == "-1" ]] && description="USB autosuspend → disabled"

    log "$description (skipping HID devices)..."
    for dev_power in /sys/bus/usb/devices/*/power/autosuspend; do
        local dev_dir
        dev_dir=$(dirname "$(dirname "$dev_power")")
        local dev_name
        dev_name=$(basename "$dev_dir")

        # Skip HID devices (keyboards, mice, touchpads)
        if [[ -d "$dev_dir" ]]; then
            local is_hid=false
            for intf in "$dev_dir"/"${dev_name}":*/bInterfaceClass; do
                if [[ -f "$intf" ]]; then
                    local class
                    class=$(cat "$intf" 2>/dev/null)
                    # Class 03 = HID
                    if [[ "$class" == "03" ]]; then
                        is_hid=true
                        break
                    fi
                fi
            done

            if $is_hid; then
                log "  [skip-hid] $dev_name"
                continue
            fi
        fi

        sysfs_write "$dev_power" "$timeout" "  $dev_name"
    done
}

show_status() {
    echo "=== USB Power Status ==="
    echo ""
    echo "USB devices and autosuspend settings:"
    
    for dev_power in /sys/bus/usb/devices/*/power/autosuspend; do
        if [[ -f "$dev_power" ]]; then
            local dev_dir
            dev_dir=$(dirname "$(dirname "$dev_power")")
            local dev_name
            dev_name=$(basename "$dev_dir")
            
            # Get product name if available
            local product=""
            if [[ -f "$dev_dir/product" ]]; then
                product=$(cat "$dev_dir/product" 2>/dev/null)
            fi
            
            # Check if HID
            local is_hid="no"
            for intf in "$dev_dir"/"${dev_name}":*/bInterfaceClass; do
                if [[ -f "$intf" ]] && [[ "$(cat "$intf" 2>/dev/null)" == "03" ]]; then
                    is_hid="HID"
                    break
                fi
            done
            
            local timeout
            timeout=$(cat "$dev_power" 2>/dev/null)
            local control
            control=$(cat "$dev_dir/power/control" 2>/dev/null)
            
            printf "  %-12s timeout=%3ss, control=%s, hid=%s" "$dev_name" "$timeout" "$control" "$is_hid"
            [[ -n "$product" ]] && printf " (%s)" "$product"
            echo ""
        fi
    done
}

apply_battery() {
    require_root
    log "=== Applying battery USB settings ==="
    
    usb_autosuspend 2
    
    log ""
    log "Battery USB settings applied"
}

apply_ac() {
    require_root
    log "=== Applying AC USB settings ==="
    
    usb_autosuspend -1
    
    log ""
    log "AC USB settings applied"
}

main() {
    local mode
    mode=$(parse_module_args "$@")
    
    case "$mode" in
        battery)  apply_battery ;;
        ac)       apply_ac ;;
        status)   show_status ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "  battery    Enable 2s autosuspend (skip HID devices)"
            echo "  ac         Disable autosuspend"
            echo "  status     Show current USB power settings"
            exit 1
            ;;
    esac
}

main "$@"
