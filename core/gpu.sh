#!/usr/bin/env bash
# =============================================================================
# gpu.sh — dGPU access control for ASUS ROG Zephyrus G16 (RTX 5090)
#
# The dGPU's power state is cardwire's job (block on battery -> the driver
# runtime-suspends it; hybrid on AC). This module only asks cardwire for the
# mode and reports status. It deliberately does NOT write dgpu_disable, does
# NOT set PCIe power/control and does NOT unload nvidia modules — removing
# or forcing the dGPU off the bus on battery costs power, not saves it.
#
# Test independently:
#   sudo ./gpu.sh battery      # cardwire integrated (dGPU idles into D3cold)
#   sudo ./gpu.sh ac           # cardwire hybrid (dGPU available for ML/gaming)
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
    echo "  battery    → cardwire integrated (dGPU idles into D3cold)"
    echo "  ac         → cardwire hybrid (dGPU available for ML/gaming)"
}

apply_battery() {
    log "=== Battery: dGPU D3cold via cardwire (no removal, no eco) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set cardwire integrated (block access -> D3cold)"
        return 0
    fi

    # Power state is cardwire's part: blocking access lets the driver
    # runtime-suspend the dGPU (D3cold). This script must NOT write
    # dgpu_disable or touch PCIe power — removing the dGPU on battery
    # costs ~20W (device leaves the bus but the rail stays powered).
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        warn "dGPU not on the bus — check cardwire/journal for what happened"
    fi

    cardwire_set_mode "integrated"
}

apply_ac() {
    log "=== AC: dGPU available (Hybrid) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set cardwire hybrid (dGPU available)"
        return 0
    fi

    # Same rule as battery: cardwire owns the dGPU. No dgpu-switch standard,
    # no service management — restoring the GPU is cardwire's + reboot's job.
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        warn "dGPU not on the bus — it returns on the next reboot"
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
            echo "  battery    cardwire integrated (dGPU idles into D3cold)"
            echo "  ac         cardwire hybrid (dGPU available)"
            echo "  status     Show current GPU power state"
            exit 1
            ;;
    esac
}

main "$@"
