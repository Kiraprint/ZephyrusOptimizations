#!/usr/bin/env bash
# =============================================================================
# audio.sh — Audio codec power management
#
# Test independently:
#   sudo ./audio.sh battery --dry-run
#   sudo ./audio.sh ac --dry-run
#   ./audio.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[audio]"

show_status() {
    echo "=== Audio Power Status ==="
    
    local power_save
    power_save=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || echo "N/A")
    echo "Power-save timeout: ${power_save}s"
    
    local controller
    controller=$(cat /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null || echo "N/A")
    echo "Codec controller PM: $controller"
    
    # Check if codec is in power-save
    if [[ -d /proc/asound ]]; then
        echo ""
        echo "Sound cards:"
        cat /proc/asound/cards 2>/dev/null | head -5
    fi
}

apply_battery() {
    require_root
    log "=== Applying battery audio settings ==="
    
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save" "60" "Power-save timeout → 60s"
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save_controller" "Y" "Codec controller PM → enabled"
    
    log ""
    log "Battery audio settings applied"
    log "Note: Codec will enter power-save after 60s of silence"
}

apply_ac() {
    require_root
    log "=== Applying AC audio settings ==="
    
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save" "0" "Power-save timeout → off"
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save_controller" "N" "Codec controller PM → disabled"
    
    log ""
    log "AC audio settings applied"
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
            echo "  battery    Enable 60s power-save timeout"
            echo "  ac         Disable power-save (always on)"
            echo "  status     Show current audio power settings"
            exit 1
            ;;
    esac
}

main "$@"
