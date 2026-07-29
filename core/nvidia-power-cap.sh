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
#   2. Optionally locking GPU & memory clocks (can skip on battery)
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
    # Wrapper so we don't fail the whole module if nvidia-smi is missing or
    # the GPU is D3cold (battery mode).
    if [[ ! -x "$NV_SMI" ]]; then
        warn "nvidia-smi not found at $NV_SMI"
        return 1
    fi
    # If GPU is not accessible (D3cold / modules unloaded), nvidia-smi will
    # return non-zero — catch that gracefully.
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
    if _nvidia_smi -pm 1; then
        log "    [ok] persistence mode enabled"
    else
        warn "    persistence mode failed (GPU may be D3cold)"
        return 1
    fi
}

lock_clocks_ac() {
    # Memory clock: lock to max (14001 MHz effective on GDDR7)
    # GPU clock: set floor to 2000 MHz, cap at HW max
    log "  Locking GPU clocks for max throughput..."

    if _nvidia_smi -lmc 14001; then
        log "    [ok] memory clock → 14001 MHz"
    else
        warn "    memory clock lock failed"
    fi

    # Query the actual max graphics clock from the card
    local gpu_max
    gpu_max=$(_nvidia_smi --query-gpu=clocks.max.graphics --format=csv,noheader 2>/dev/null | head -1 | tr -d ' MHz' || echo "3090")
    if _nvidia_smi -lgc 2000,"$gpu_max" 2>/dev/null; then
        log "    [ok] GPU clock → 2000–${gpu_max} MHz"
    else
        # -lgc may not be supported on all driver versions; non-fatal
        warn "    GPU clock lock not supported (non-fatal)"
    fi
}

unlock_clocks() {
    # Reset clocks to default (for battery mode — GPU is D3cold anyway)
    log "  Resetting GPU clocks to driver defaults..."
    _nvidia_smi -rgc 2>/dev/null || true
    _nvidia_smi -rmc 2>/dev/null || true
    log "    [ok] clocks reset"
}

trigger_power_renegotiation() {
    # The key trick: nvidia-smi -pm 1 causes the driver to re-read the VBIOS
    # power table and negotiate with the EC/firmware.  After this the power
    # limit usually climbs from ~108 W to ~150–167 W on GU605CX + RTX 5090.
    #
    # We also do a dummy read of the power limit to force the new value to
    # propagate.
    log "  Triggering power budget renegotiation..."
    local before after
    before=$(_nvidia_smi --query-gpu=power.limit --format=csv,noheader 2>/dev/null | head -1 || echo "?")
    # Re-run PM enable (idempotent) as the trigger
    _nvidia_smi -pm 1 &>/dev/null
    # Read limit again to force propagation
    after=$(_nvidia_smi --query-gpu=power.limit --format=csv,noheader 2>/dev/null | head -1 || echo "?")
    log "    power limit: $before → $after"
}

# --- Public commands ---------------------------------------------------------

apply_ac() {
    log "=== NVIDIA Power Cap: Unlock (AC mode) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would enable persistence mode, lock clocks, renegotiate power"
        return 0
    fi

    # 1. Enable persistence mode (required for renegotiation)
    enable_persistence_mode || return 1

    # 2. Lock clocks for max throughput
    lock_clocks_ac

    # 3. Trigger power budget renegotiation
    trigger_power_renegotiation

    log "=== NVIDIA Power Cap unlock complete ==="
}

apply_battery() {
    log "=== NVIDIA Power Cap: Reset (battery mode) ==="
    # On battery the dGPU is typically D3cold and NVIDIA modules may be
    # unloaded.  Just reset any clock locks so they don't persist across
    # mode switches.
    unlock_clocks
    log "=== NVIDIA Power Cap reset complete ==="
}

show_status() {
    echo "=== NVIDIA Power Cap ==="

    # VBIOS max (NVML via nvidia-smi)
    local vbios_max driver_current ec_nv_tgp ec_base ec_boost
    vbios_max="?"
    driver_current="?"
    if _nvidia_smi -q -d POWER &>/dev/null; then
        vbios_max=$(_nvidia_smi -q -d POWER 2>/dev/null | grep "Max Power Limit" | head -1 | awk '{print $5}')
        driver_current=$(_nvidia_smi --query-gpu=power.limit --format=csv,noheader 2>/dev/null | head -1 | tr -d ' W')
        [[ -z "$driver_current" || "$driver_current" == "[N/A]" ]] && driver_current="?"
    fi

    # EC firmware attributes (asus-armoury sysfs)
    ec_nv_tgp=$(_read_sysfs nv_tgp)
    ec_base=$(_read_sysfs nv_base_tgp)
    ec_boost=$(_read_sysfs nv_dynamic_boost)

    echo "  VBIOS max limit : ${vbios_max}W"
    echo "  Driver current  : ${driver_current}W"
    echo "  EC nv_tgp       : ${ec_nv_tgp}W"
    echo "  EC nv_base_tgp  : ${ec_base}W"
    echo "  EC dyn_boost    : ${ec_boost}W"

    # Compute gap
    if [[ "$vbios_max" != "?" && "$driver_current" != "?" ]]; then
        local gap
        gap=$((vbios_max - driver_current))
        if [[ "$gap" -gt 0 ]]; then
            echo "  Headroom left   : ${gap}W"
        elif [[ "$gap" -eq 0 ]]; then
            echo "  Headroom left   : 0W (at VBIOS max!)"
        fi
    fi

    # Check persistence mode
    local pm
    pm=$(_nvidia_smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | head -1 || echo "?")
    echo "  Persistence     : ${pm}"

    # Check clock locks
    local gpu_clock mem_clock
    gpu_clock=$(_nvidia_smi --query-gpu=clocks.current.graphics --format=csv,noheader 2>/dev/null | head -1 || echo "?")
    mem_clock=$(_nvidia_smi --query-gpu=clocks.current.memory --format=csv,noheader 2>/dev/null | head -1 || echo "?")
    if [[ "$gpu_clock" != "?" && "$gpu_clock" != "[N/A]" ]]; then
        gpu_clock=$(echo "$gpu_clock" | tr -d ' MHz')
    fi
    if [[ "$mem_clock" != "?" && "$mem_clock" != "[N/A]" ]]; then
        mem_clock=$(echo "$mem_clock" | tr -d ' MHz')
    fi
    echo "  GPU clock       : ${gpu_clock} MHz"
    echo "  Mem clock       : ${mem_clock} MHz"

    echo "  Management:"
    echo "    ac        → sudo ./nvidia-power-cap.sh ac"
    echo "    battery   → sudo ./nvidia-power-cap.sh battery"
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
            echo ""
            echo "  ac         Unlock NVIDIA power cap (persistence + clocks + renegotiation)"
            echo "  battery    Reset NVIDIA clock locks (GPU is D3cold anyway)"
            echo "  status     Show VBIOS max / driver limit / EC cap / clocks"
            exit 1
            ;;
    esac
}

main "$@"
