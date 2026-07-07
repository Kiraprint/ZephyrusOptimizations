#!/usr/bin/env bash
# =============================================================================
# igpu-freq.sh — Intel integrated GPU frequency scaling
#
# Test independently:
#   sudo ./igpu-freq.sh battery --dry-run
#   sudo ./igpu-freq.sh ac --dry-run
#   ./igpu-freq.sh status
#
# Intel Arc iGPU frequency control for power savings on battery
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[igpu-freq]"

# Intel GPU sysfs paths - detect Intel card (vendor 0x8086)
detect_intel_gpu_card() {
    for card in /sys/class/drm/card[0-9]; do
        if [[ -f "$card/device/vendor" ]]; then
            local vendor
            vendor=$(cat "$card/device/vendor" 2>/dev/null)
            if [[ "$vendor" == "0x8086" ]]; then
                echo "$card"
                return 0
            fi
        fi
    done
    return 1
}

GPU_CARD=$(detect_intel_gpu_card)
GPU_MIN_FREQ="$GPU_CARD/gt_min_freq_mhz"
GPU_MAX_FREQ="$GPU_CARD/gt_max_freq_mhz"
GPU_BOOST_FREQ="$GPU_CARD/gt_boost_freq_mhz"
GPU_CUR_FREQ="$GPU_CARD/gt_cur_freq_mhz"
GPU_RP0_FREQ="$GPU_CARD/gt_RP0_freq_mhz"  # Max non-turbo
GPU_RP1_FREQ="$GPU_CARD/gt_RP1_freq_mhz"  # Efficient performance
GPU_RPn_FREQ="$GPU_CARD/gt_RPn_freq_mhz"  # Min supported

show_status() {
    echo "=== Intel iGPU Frequency Status ==="
    
    if [[ -z "$GPU_CARD" ]] || [[ ! -d "$GPU_CARD" ]]; then
        echo "Intel iGPU not found"
        return 1
    fi
    
    echo "Intel iGPU: $GPU_CARD"
    echo ""
    
    local cur_freq min_freq max_freq boost_freq
    cur_freq=$(cat "$GPU_CUR_FREQ" 2>/dev/null || echo "N/A")
    min_freq=$(cat "$GPU_MIN_FREQ" 2>/dev/null || echo "N/A")
    max_freq=$(cat "$GPU_MAX_FREQ" 2>/dev/null || echo "N/A")
    boost_freq=$(cat "$GPU_BOOST_FREQ" 2>/dev/null || echo "N/A")
    
    echo "Current frequency: ${cur_freq} MHz"
    echo "Min frequency   : ${min_freq} MHz"
    echo "Max frequency   : ${max_freq} MHz"
    echo "Boost frequency : ${boost_freq} MHz"
    
    echo ""
    echo "Hardware limits:"
    
    if [[ -f "$GPU_RPn_FREQ" ]]; then
        local rpn_freq rp1_freq rp0_freq
        rpn_freq=$(cat "$GPU_RPn_FREQ" 2>/dev/null || echo "N/A")
        rp1_freq=$(cat "$GPU_RP1_FREQ" 2>/dev/null || echo "N/A")
        rp0_freq=$(cat "$GPU_RP0_FREQ" 2>/dev/null || echo "N/A")
        
        echo "  RPn (min supported) : ${rpn_freq} MHz"
        echo "  RP1 (efficient)     : ${rp1_freq} MHz"
        echo "  RP0 (max non-turbo) : ${rp0_freq} MHz"
    fi
}

apply_battery() {
    require_root
    log "=== Applying battery iGPU frequency settings ==="
    
    if [[ -z "$GPU_CARD" ]] || [[ ! -d "$GPU_CARD" ]]; then
        warn "Intel iGPU not found - skipping"
        return 0
    fi
    
    # Get hardware limits
    local rpn_freq rp1_freq cur_min
    rpn_freq=$(cat "$GPU_RPn_FREQ" 2>/dev/null || echo "300")
    rp1_freq=$(cat "$GPU_RP1_FREQ" 2>/dev/null || echo "1100")
    cur_min=$(cat "$GPU_MIN_FREQ" 2>/dev/null || echo "$rpn_freq")

    # On battery: cap MAX to RP1 (efficient perf) to cut power under GPU load,
    # but NEVER raise the idle floor — idle is the dominant battery state.
    # Some Xe/Arc parts misreport RPn above the true floor (e.g. RPn=800 while
    # gt_min=100), so keep the lowest of (current min, RPn).
    local target_min="$rpn_freq"
    [[ "$cur_min" -lt "$target_min" ]] 2>/dev/null && target_min="$cur_min"
    local target_max="$rp1_freq"

    log "Target: min=${target_min}MHz, max=${target_max}MHz (RP1 cap, idle floor preserved)"
    
    # Set min frequency first (to avoid issues if current max < new min)
    if [[ -w "$GPU_MIN_FREQ" ]]; then
        sysfs_write "$GPU_MIN_FREQ" "$target_min" "iGPU min frequency → ${target_min}MHz"
    else
        log "  [skip] iGPU min freq not writable"
    fi
    
    # Then set max frequency
    if [[ -w "$GPU_MAX_FREQ" ]]; then
        sysfs_write "$GPU_MAX_FREQ" "$target_max" "iGPU max frequency → ${target_max}MHz"
    else
        log "  [skip] iGPU max freq not writable"
    fi
    
    # Optionally disable boost on battery
    if [[ -w "$GPU_BOOST_FREQ" ]]; then
        sysfs_write "$GPU_BOOST_FREQ" "$target_max" "iGPU boost frequency → ${target_max}MHz"
    fi
    
    log ""
    log "Battery iGPU frequency settings applied"
    log "Note: iGPU will now operate between ${target_min}-${target_max}MHz"
}

apply_ac() {
    require_root
    log "=== Applying AC iGPU frequency settings ==="
    
    if [[ -z "$GPU_CARD" ]] || [[ ! -d "$GPU_CARD" ]]; then
        warn "Intel iGPU not found - skipping"
        return 0
    fi
    
    # Get hardware limits
    local rpn_freq rp0_freq
    rpn_freq=$(cat "$GPU_RPn_FREQ" 2>/dev/null || echo "300")
    rp0_freq=$(cat "$GPU_RP0_FREQ" 2>/dev/null || echo "2000")
    
    # On AC: Allow full frequency range
    local target_min="$rpn_freq"
    local target_max="$rp0_freq"
    
    log "Target: min=${target_min}MHz, max=${target_max}MHz (full performance)"
    
    # Try to reset to defaults - may fail if hardware only supports specific frequencies
    if [[ -w "$GPU_MAX_FREQ" ]]; then
        # Try setting max (may fail if only discrete freqs supported)
        sysfs_write "$GPU_MAX_FREQ" "$target_max" "iGPU max frequency → ${target_max}MHz" || true
    else
        log "  [skip] iGPU max freq not writable"
    fi
    
    if [[ -w "$GPU_MIN_FREQ" ]]; then
        sysfs_write "$GPU_MIN_FREQ" "$target_min" "iGPU min frequency → ${target_min}MHz" || true
    else
        log "  [skip] iGPU min freq not writable"
    fi
    
    if [[ -w "$GPU_BOOST_FREQ" ]]; then
        sysfs_write "$GPU_BOOST_FREQ" "$target_max" "iGPU boost frequency → ${target_max}MHz" || true
    fi
    
    log ""
    log "AC iGPU frequency settings applied"
    log "Note: Some Intel Arc GPUs only support discrete frequency levels"
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
            echo "  battery    Limit iGPU to RP1 frequency (power savings)"
            echo "  ac         Allow full iGPU frequency range (performance)"
            echo "  status     Show current iGPU frequency settings"
            echo ""
            echo "NOTE: Intel Arc iGPU frequency scaling for power optimization"
            exit 1
            ;;
    esac
}

main "$@"
