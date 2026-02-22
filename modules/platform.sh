#!/usr/bin/env bash
# =============================================================================
# platform.sh — ACPI platform profile management
#
# Test independently:
#   sudo ./platform.sh battery --dry-run
#   sudo ./platform.sh ac --dry-run
#   ./platform.sh status
#
# NOTE: asusctl may also manage this, but explicit setting ensures consistency
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[platform]"

PLATFORM_PROFILE="/sys/firmware/acpi/platform_profile"
PLATFORM_CHOICES="/sys/firmware/acpi/platform_profile_choices"

show_status() {
    echo "=== Platform Profile Status ==="
    
    if [[ -f "$PLATFORM_PROFILE" ]]; then
        local current
        current=$(cat "$PLATFORM_PROFILE" 2>/dev/null)
        echo "Current profile: $current"
    else
        echo "Platform profile not available"
    fi
    
    if [[ -f "$PLATFORM_CHOICES" ]]; then
        local choices
        choices=$(cat "$PLATFORM_CHOICES" 2>/dev/null)
        echo "Available: $choices"
    fi
    
    # asusctl status
    if command -v asusctl &>/dev/null; then
        echo ""
        echo "asusctl profile:"
        asusctl profile -p 2>/dev/null || echo "  (not available)"
    fi
}

apply_battery() {
    require_root
    log "=== Applying battery platform profile ==="
    
    # Note: asusctl auto-switches to Quiet on battery, so we don't override
    # But we verify the state
    
    if [[ -f "$PLATFORM_PROFILE" ]]; then
        local current
        current=$(cat "$PLATFORM_PROFILE" 2>/dev/null)
        log "Current platform profile: $current"
        
        if [[ "$current" == "quiet" ]] || [[ "$current" == "low-power" ]]; then
            log "  [ok] Already in power-saving profile"
        else
            log "  [info] Profile is '$current' — asusctl should switch to Quiet automatically"
        fi
    fi
    
    log ""
    log "NOTE: asusctl handles battery profile switching automatically"
}

apply_ac() {
    require_root
    log "=== Applying AC platform profile ==="
    
    if [[ -f "$PLATFORM_PROFILE" ]]; then
        sysfs_write "$PLATFORM_PROFILE" "performance" "Platform profile → performance"
    else
        warn "Platform profile not available"
    fi
    
    log ""
    log "AC platform profile applied"
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
            echo "  battery    Verify/set battery profile (usually 'quiet')"
            echo "  ac         Set 'performance' profile"
            echo "  status     Show current platform profile"
            exit 1
            ;;
    esac
}

main "$@"
