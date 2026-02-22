#!/usr/bin/env bash
# =============================================================================
# cpu-cores.sh — CPU core offlining/onlining module
#
# Test independently:
#   sudo ./cpu-cores.sh battery --dry-run  # Preview offlining
#   sudo ./cpu-cores.sh ac --dry-run       # Preview onlining
#   ./cpu-cores.sh status                  # Show current state
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[cpu-cores]"

# Core offlining DISABLED - Intel Thread Director + RAPL is more efficient
# Testing showed offlining cores doesn't save power on Arrow Lake due to:
#   1. Idle cores already in deep C-states (near 0W)  
#   2. Scheduler overhead increases with fewer cores
#   3. Thread Director handles core selection optimally

show_status() {
    echo "=== CPU Core Status ==="
    local online_count=0
    local offline_count=0
    local online_list=""
    local offline_list=""
    
    for i in $(seq 0 15); do
        local path="/sys/devices/system/cpu/cpu${i}/online"
        if [[ "$i" -eq 0 ]] || { [[ -f "$path" ]] && [[ "$(cat "$path" 2>/dev/null)" == "1" ]]; }; then
            online_count=$((online_count + 1))
            online_list+="$i "
        else
            offline_count=$((offline_count + 1))
            offline_list+="$i "
        fi
    done
    
    echo "Online ($online_count)  : cpu{$online_list}"
    echo "Offline ($offline_count) : ${offline_list:-(none)}"
    
    echo ""
    echo "Core mapping:"
    echo "  P-cores (Lion Cove)  : cpu0-5   (max 5400 MHz)"
    echo "  E-cores (Skymont)    : cpu6-13  (max 4500 MHz)"
    echo "  LP E-cores           : cpu14-15 (max 2500 MHz)"
    echo ""
    echo "Note: Core offlining disabled - RAPL + Thread Director is more efficient"
}

apply_battery() {
    log "=== CPU cores for battery mode ==="
    log "  [info] All 16 cores stay online"
    log "  [info] Intel Thread Director + RAPL cap is more power-efficient"
    log "  [info] than manual core offlining on Arrow Lake"
    log ""
    log "Power savings come from:"
    log "  - RAPL package power limit (cpu-power module)"
    log "  - EPP = power (cpu-power module)"
    log "  - Turbo disabled (cpu-power module)"
}

apply_ac() {
    log "=== CPU cores for AC mode ==="
    log "  [info] All 16 cores online (default)"
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
            echo "  battery    Offline 11 cores (cpu1-5, cpu10-15), keep 5 online"
            echo "  ac         Online all 16 cores"
            echo "  status     Show current core status"
            exit 1
            ;;
    esac
}

main "$@"
