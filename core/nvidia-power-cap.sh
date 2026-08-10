#!/usr/bin/env bash
# =============================================================================
# nvidia-power-cap.sh — Unlock full VBIOS power cap on NVIDIA RTX 5090
#
# The ASUS EC caps dGPU TGP at ~110 W via firmware attributes (nv_tgp range
# 95–110, nv_base_tgp locked at 95).  However the GPU VBIOS supports up to
# 175 W.  This module triggers the NVIDIA driver to renegotiate the power
# budget past the EC ceiling by:
#
#   1. Enabling persistence mode (nvidia-smi -pm 1)
#   2. Optionally locking GPU & memory clocks
#   3. Reporting the gap between VBIOS max, driver limit, and EC cap
#
# Depends: nvidia-smi, asus-armoury driver (sysfs)
#
# Test:
#   sudo ./nvidia-power-cap.sh ac
#   ./nvidia-power-cap.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[nvidia-power-cap]"

# --- Paths -------------------------------------------------------------------
NV_SMI="/usr/bin/nvidia-smi"
ASUS_ATTR_BASE="/sys/devices/virtual/firmware-attributes/asus-armoury/attributes"

# --- Helpers -----------------------------------------------------------------

_nvidia_smi() {
    if [[ ! -x "$NV_SMI" ]]; then
        warn "nvidia-smi not found at $NV_SMI"
        return 1
    fi
    "$NV_SMI" "$@" 2>/dev/null || return 1
}

_read_sysfs() {
    local attr="$1"
    local field="${2:-current_value}"
    local path="$ASUS_ATTR_BASE/$attr/$field"
    if [[ -r "$path" ]]; then
        cat "$path" 2>/dev/null || echo "?"
    else
        echo "N/A"
    fi
}

# --- Core logic --------------------------------------------------------------

enable_persistence_mode() {
    log "  Enabling NVIDIA persistence mode..."
    # GPU may be in D3cold at boot — retry until it responds
    local pm_before=""
    for attempt in 1 2 3 4 5; do
        if _nvidia_smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | head -1 | grep -qi enabled; then
            pm_before="enabled"
            break
        fi
        if _nvidia_smi -pm 1 2>/dev/null; then
            pm_before="disabled"
            break
        fi
        warn "    attempt $attempt: GPU not responding (D3cold?) — retrying in 5s"
        sleep 5
    done
    if [[ -z "$pm_before" ]]; then
        warn "    persistence mode failed after 5 attempts"
        return 1
    fi
    # Force renegotiation: toggle persistence mode (disable -> enable)
    # so the driver re-reads the power budget from the VBIOS.
    if [[ "$pm_before" == "enabled" ]]; then
        log "    persistence already enabled — toggling to force power renegotiation"
        _nvidia_smi -pm 0 2>/dev/null
        sleep 1
    fi
    if _nvidia_smi -pm 1 2>/dev/null; then
        log "    [ok] persistence mode enabled (power budget renegotiated)"
        return 0
    fi
    warn "    persistence mode failed to re-enable"
    return 1
}

set_armoury_tgp() {
    # Push ASUS EC TGP attributes to their max allowed range.
    # This signals the EC to release the power budget so the NVIDIA driver
    # can negotiate a higher limit (up to VBIOS max, ~175 W).
    log "  Setting ASUS EC TGP attributes to max..."
    if command -v asusctl &>/dev/null; then
        asusctl armoury set nv_tgp 110 &>/dev/null || true
        asusctl armoury set nv_dynamic_boost 20 &>/dev/null || true
        log "    [ok] nv_tgp=110  nv_dynamic_boost=20"
    else
        warn "    asusctl not found — skipping EC TGP negotiation"
    fi
}

lock_clocks_ac() {
    log "  Locking GPU clocks for max throughput..."
    if _nvidia_smi -lmc 14001; then
        log "    [ok] memory clock → 14001 MHz"
    else
        warn "    memory clock lock failed"
    fi
    local gpu_max
    gpu_max=$(_nvidia_smi --query-gpu=clocks.max.graphics --format=csv,noheader 2>/dev/null | head -1 | tr -d ' MHz' || echo "3090")
    if _nvidia_smi -lgc 2000,"$gpu_max" 2>/dev/null; then
        log "    [ok] GPU clock → 2000–${gpu_max} MHz"
    else
        warn "    GPU clock lock not supported (non-fatal)"
    fi
}

unlock_clocks() {
    log "  Resetting GPU clocks to driver defaults..."
    _nvidia_smi -rgc 2>/dev/null || true
    _nvidia_smi -rmc 2>/dev/null || true
    log "    [ok] clocks reset"
}

trigger_power_renegotiation() {
    log "  Triggering power budget renegotiation..."
    local before after
    before=$(_nvidia_smi --query-gpu=power.limit --format=csv,noheader 2>/dev/null | head -1 | sed "s| MHz||" || echo "?")
    _nvidia_smi -pm 1 &>/dev/null
    after=$(_nvidia_smi --query-gpu=power.limit --format=csv,noheader 2>/dev/null | head -1 | sed "s| MHz||" || echo "?")
    log "    power limit: $before → $after"
}

# --- Public commands ---------------------------------------------------------

apply_ac() {
    log "=== NVIDIA Power Cap: Unlock (AC mode) ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would enable persistence mode, lock clocks, renegotiate"
        return 0
    fi
    # 1. Push EC TGP attributes (works even while GPU is D3cold)
    set_armoury_tgp
    # 2. Enable persistence mode (retries until GPU wakes from D3cold)
    enable_persistence_mode || return 1
    # 3. Reset clocks to clear any stale locked state
    unlock_clocks
    # 4. Lock clocks for max throughput
    lock_clocks_ac
    # 5. Trigger power budget renegotiation
    trigger_power_renegotiation
    log "=== NVIDIA Power Cap unlock complete ==="
}

apply_battery() {
    log "=== NVIDIA Power Cap: Reset (battery mode) ==="
    unlock_clocks
    # Also optionally drop EC TGP to save power on battery
    if command -v asusctl &>/dev/null; then
        asusctl armoury set nv_dynamic_boost 5 &>/dev/null || true
        log "    nv_dynamic_boost → 5 (battery save)"
    fi
    log "=== NVIDIA Power Cap reset complete ==="
}

show_status() {
    echo "=== NVIDIA Power Cap ==="
    local vbios_max driver_current ec_nv_tgp ec_base ec_boost
    vbios_max="?"
    driver_current="?"
    if _nvidia_smi -q -d POWER &>/dev/null; then
        local power_info
        power_info=$(_nvidia_smi -q -d POWER 2>/dev/null)
        vbios_max=$(echo "$power_info" | grep "Max Power Limit" | head -1 | awk '{print $5}')
        driver_current=$(echo "$power_info" | grep -A1 "GPU Ceiling" | grep "Current Power" | awk '{print $5}' | tr -d " W")
        [[ -z "$driver_current" || "$driver_current" == "N/A" ]] && driver_current="?"
    fi
    ec_nv_tgp=$(_read_sysfs nv_tgp)
    ec_base=$(_read_sysfs nv_base_tgp)
    ec_boost=$(_read_sysfs nv_dynamic_boost)
    echo "  VBIOS max limit : ${vbios_max}W"
    echo "  Driver current  : ${driver_current}W"
    echo "  EC nv_tgp       : ${ec_nv_tgp}W"
    echo "  EC nv_base_tgp  : ${ec_base}W"
    echo "  EC dyn_boost    : ${ec_boost}W"
    if [[ "$vbios_max" != "?" && "$driver_current" != "?" ]]; then
        local gap=$(( ${vbios_max%%.*} - ${driver_current%%.*} ))
        if [[ "$gap" -gt 0 ]]; then
            echo "  Headroom left   : ${gap}W"
        elif [[ "$gap" -eq 0 ]]; then
            echo "  Headroom left   : 0W (at VBIOS max!)"
        fi
    fi
    local pm
    pm=$(_nvidia_smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | head -1 | sed "s| MHz||" || echo "?")
    echo "  Persistence     : ${pm}"
    local gpu_clock mem_clock
    gpu_clock=$(_nvidia_smi --query-gpu=clocks.current.graphics --format=csv,noheader 2>/dev/null | head -1 | sed "s| MHz||" || echo "?")
    mem_clock=$(_nvidia_smi --query-gpu=clocks.current.memory --format=csv,noheader 2>/dev/null | head -1 | sed "s| MHz||" || echo "?")
    echo "  GPU clock       : ${gpu_clock} MHz"
    echo "  Mem clock       : ${mem_clock} MHz"
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
            echo "Usage: $0 {ac|battery|status} [--dry-run]"
            exit 1
            ;;
    esac
}

main "$@"
