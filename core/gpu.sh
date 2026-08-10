#!/usr/bin/env bash
# =============================================================================
# gpu.sh — GPU power management for ASUS ROG Zephyrus G16 (RTX 5090)
#
# Power mechanism: NVIDIA runtime D3 (NVreg_DynamicPowerManagement=0x02).
# The driver suspends the dGPU (D3/D3cold) when idle; cardwire blocks access
# on battery so nothing wakes it. Firmware dgpu_disable (ASUS EC power cut)
# is intentionally NOT used — it removes the device from the bus and needs
# a reboot to restore (see PLAN.md: D3cold wake bug, RTX 5090 + nvidia-open).
#
# Test independently:
#   sudo ./gpu.sh battery      # Block dGPU access (idles into D3)
#   sudo ./gpu.sh ac           # Restore dGPU access (hybrid)
#   ./gpu.sh status            # Show current state
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[gpu]"

# Timeout for dgpu-switch operations (in seconds)
DGPU_TIMEOUT=10
DGPU_SWITCH="/usr/local/bin/dgpu-switch.sh"

# Cardwire — eBPF-based GPU access control (not power!)
CARDWIRE_CMD="/usr/bin/cardwire"

cardwire_available() {
    [[ -x "$CARDWIRE_CMD" ]] && systemctl is-active --quiet cardwired 2>/dev/null
}

cardwire_set_mode() {
    local mode="$1"
    if cardwire_available; then
        local out
        out=$(timeout 5 "$CARDWIRE_CMD" set "$mode" 2>&1) || true
        if echo "$out" | grep -qi "has been set"; then
            log "  cardwire: mode → $mode"
        else
            warn "cardwire set $mode: $out"
        fi
    fi
}

cardwire_show_mode() {
    if cardwire_available; then
        local mode
        mode=$("$CARDWIRE_CMD" get 2>/dev/null | head -1 | sed 's/Current Mode: //')
        echo "  cardwire mode: $mode"

        "$CARDWIRE_CMD" list 2>/dev/null | tail -n +3 | while read -r id _ rest; do
            local pci blocked
            pci=$(echo "$rest" | grep -oP '0000:[0-9a-f:\.]+' || echo "")
            blocked=$(echo "$rest" | awk '{print $NF}')
            if [[ "$blocked" == "true" ]]; then
                echo "    $pci → BLOCKED"
            fi
        done
    fi
}

show_status() {
    echo "=== GPU Power State ==="

    # Our dgpu-switch.sh status
    if [[ -x "$DGPU_SWITCH" ]]; then
        # Use it for the core status
        "$DGPU_SWITCH" status 2>&1 | tail -n +2
    else
        # Fallback: direct sysfs
        local dgpu_disable
        dgpu_disable=$(cat /sys/devices/platform/asus-nb-wmi/dgpu_disable 2>/dev/null || echo "?")
        echo "  dgpu_disable: $dgpu_disable"
    fi

    echo ""
    echo "Cardwire (eBPF access control):"
    cardwire_show_mode

    echo ""
    echo "Management:"
    echo "  battery    → cardwire integrated (dGPU sleeps via runtime D3)"
    echo "  ac         → cardwire hybrid (dGPU available)"
}

apply_battery() {
    log "=== Battery: dGPU runtime D3 (no firmware dgpu_disable) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set cardwire integrated (block access, allow D3)"
        return 0
    fi

    # Power mechanism is NVIDIA runtime D3 (NVreg_DynamicPowerManagement):
    # the driver suspends the GPU when idle. Firmware dgpu_disable (ASUS EC
    # power cut) is intentionally NOT used — on this platform it removes the
    # device from the bus and needs a reboot to restore.
    # Keep the nvidia modules + services loaded so runtime PM stays active.
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        warn "GPU not present on the bus — check journal for D3cold removal"
    else
        log "  [ok] GPU present — will enter D3 when idle (Video Memory: Off)"
    fi

    # Block dGPU access so nothing wakes it; it then idles into D3
    cardwire_set_mode "integrated"
}

apply_ac() {
    log "=== AC: dGPU available (Hybrid) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set cardwire hybrid (restore dGPU access)"
        return 0
    fi

    # nvidia-powerd and module lifecycle are NOT managed here: cardwire owns
    # mode switching, and nvidia-powerd is guarded (see nvidia-powerd-guard)
    # so restarts against an absent GPU are safe no-ops.
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        warn "dGPU not on the bus (D3cold removal) — returns after reboot"
    fi

    cardwire_set_mode "hybrid"
}

main() {
    # Parse --dry-run BEFORE command substitution (subshell bug workaround)
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
            echo "  battery    Block dGPU access (idles into runtime D3)"
            echo "  ac         Restore dGPU access (hybrid)"
            echo "  status     Show current GPU power state"
            exit 1
            ;;
    esac
}

main "$@"
