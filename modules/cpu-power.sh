#!/usr/bin/env bash
# =============================================================================
# cpu-power.sh — CPU power settings (turbo, EPP, HWP, RAPL, min_perf_pct)
#
# Test independently:
#   sudo ./cpu-power.sh battery --dry-run
#   sudo ./cpu-power.sh ac --dry-run
#   ./cpu-power.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[cpu-power]"

# RAPL power limits (in microwatts)
# Intel 285H specs: PBP=45W, MTP=115W, Min Assured=35W
# Testing showed: 5W=laggy, 10W=responsive, diminishing returns above 12W
RAPL_PL1_BATTERY=8000000     # 8W sustained (power save, still usable)
RAPL_PL2_BATTERY=20000000    # 20W burst (for UI responsiveness)
RAPL_PL1_AC=110000000        # 110W sustained
RAPL_PL2_AC=110000000        # 110W burst

RAPL_PL1="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw"
RAPL_PL2="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw"

set_epp_all() {
    local epp="$1"
    log "Setting EPP to '$epp' on all online cores..."
    for epp_path in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        local cpu_num
        cpu_num=$(echo "$epp_path" | grep -oP 'cpu\K[0-9]+')
        local online_path="/sys/devices/system/cpu/cpu${cpu_num}/online"

        # cpu0 has no 'online' file — it's always online
        if [[ -f "$online_path" ]]; then
            local is_online
            is_online=$(cat "$online_path" 2>/dev/null)
            [[ "$is_online" != "1" ]] && continue
        fi

        sysfs_write "$epp_path" "$epp" "  cpu${cpu_num} EPP"
    done
}

show_status() {
    echo "=== CPU Power Status ==="
    
    local turbo
    turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
    echo "Turbo boost     : $( [[ "$turbo" == "0" ]] && echo "ENABLED" || echo "disabled" )"

    local hwp
    hwp=$(cat /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost 2>/dev/null)
    echo "HWP dyn. boost  : $( [[ "$hwp" == "1" ]] && echo "enabled" || echo "disabled" )"

    local epp
    epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
    echo "EPP (cpu0)      : $epp"

    local min_perf
    min_perf=$(cat /sys/devices/system/cpu/intel_pstate/min_perf_pct 2>/dev/null)
    echo "min_perf_pct    : ${min_perf}%"

    local pl1
    pl1=$(cat "$RAPL_PL1" 2>/dev/null)
    local pl2
    pl2=$(cat "$RAPL_PL2" 2>/dev/null)
    echo "RAPL PL1 (sust) : $((pl1 / 1000000))W"
    echo "RAPL PL2 (burst): $((pl2 / 1000000))W"
    
    echo ""
    echo "Current frequencies:"
    for i in 0 6 14; do
        local freq
        freq=$(cat /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_cur_freq 2>/dev/null)
        if [[ -n "$freq" ]]; then
            printf "  cpu%d: %d MHz\n" "$i" "$((freq / 1000))"
        fi
    done
}

apply_battery() {
    require_root
    log "=== Applying battery CPU power settings ==="
    
    # RAPL power capping DISABLED — causes lags with Brave + Cursor at 15W+
    # sysfs_write "$RAPL_PL1" "$RAPL_PL1_BATTERY" "PL1 (sustained) → $((RAPL_PL1_BATTERY / 1000000))W"
    # sysfs_write "$RAPL_PL2" "$RAPL_PL2_BATTERY" "PL2 (burst) → $((RAPL_PL2_BATTERY / 1000000))W"

    log "--- CPU governor settings ---"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/no_turbo" "1" "Turbo boost → disabled"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost" "0" "HWP dynamic boost → disabled"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "8" "min_perf_pct → 8%"

    log ""
    set_epp_all "power"
    
    log ""
    log "Battery CPU power settings applied"
}

apply_ac() {
    require_root
    log "=== Applying AC CPU power settings ==="
    
    log "--- RAPL power limits ---"
    sysfs_write "$RAPL_PL1" "$RAPL_PL1_AC" "PL1 (sustained) → $((RAPL_PL1_AC / 1000000))W"
    sysfs_write "$RAPL_PL2" "$RAPL_PL2_AC" "PL2 (burst) → $((RAPL_PL2_AC / 1000000))W"

    log ""
    log "--- CPU governor settings ---"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/no_turbo" "0" "Turbo boost → enabled"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost" "1" "HWP dynamic boost → enabled"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "30" "min_perf_pct → 30%"

    log ""
    set_epp_all "performance"
    
    log ""
    log "AC CPU power settings applied"
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
            echo "  battery    Low power (3W cap, no turbo, EPP=power)"
            echo "  ac         Full power (110W, turbo on, EPP=performance)"
            echo "  status     Show current CPU power settings"
            exit 1
            ;;
    esac
}

main "$@"
