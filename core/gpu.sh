#!/usr/bin/env bash
# =============================================================================
# gpu.sh — GPU power management for ASUS ROG Zephyrus G16 (RTX 5090)
#
# Integrated with dgpu-switch.sh for ACPI-level dGPU power control
#   - Eco mode (battery): dgpu_disable=1, 0W on dGPU
#   - Standard (AC):      dgpu_disable=0, restore GPU (may need reboot)
#
# Test independently:
#   sudo ./gpu.sh battery      # Power off dGPU (may need logout)
#   sudo ./gpu.sh ac           # Restore dGPU
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
    echo "  battery    → sudo dgpu-switch.sh eco + cardwire integrated"
    echo "  ac         → sudo dgpu-switch.sh standard (or reboot) + cardwire hybrid"
}

apply_battery() {
    log "=== Eco: dGPU power off (battery mode) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would power off dGPU (dgpu_disable=1) + cardwire integrated"
        return 0
    fi

    if [[ ! -x "$DGPU_SWITCH" ]]; then
        warn "dgpu-switch.sh not found at $DGPU_SWITCH"
        warn "Install it first, or manually: echo 1 > /sys/devices/platform/asus-nb-wmi/dgpu_disable"
        return 1
    fi

    # Run eco mode — will fail gracefully if NVIDIA is in use
    local output
    output=$(timeout "$DGPU_TIMEOUT" "$DGPU_SWITCH" eco 2>&1) || true

    if echo "$output" | grep -q "ERROR: NVIDIA in use"; then
        warn "dGPU is in use by user processes — cannot power off."
        warn "Log out first, then unplug AC again, or run manually:"
        warn "  sudo dgpu-switch.sh eco"
        warn ""
        warn "Processes blocking dGPU power-off:"
        echo "$output" | grep -E "^\s+[A-Z]"
        return 1
    fi

    cardwire_set_mode "integrated"

    if echo "$output" | grep -q "Eco\|Confirmed\|ECO"; then
        log "  [ok] dGPU powered off (dgpu_disable=1, 0W)"
    else
        log "  $output"
    fi
}

apply_ac() {
    log "=== Standard: dGPU power on (AC mode) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would restore dGPU power (dgpu_disable=0) + cardwire hybrid"
        return 0
    fi

    if [[ ! -x "$DGPU_SWITCH" ]]; then
        warn "dgpu-switch.sh not found at $DGPU_SWITCH"
        return 1
    fi

    local output
    output=$(timeout "$DGPU_TIMEOUT" "$DGPU_SWITCH" standard 2>&1) || true

    cardwire_set_mode "hybrid"

    if echo "$output" | grep -q "SUCCESS"; then
        log "  [ok] dGPU fully restored and ready"
    elif echo "$output" | grep -q "PARTIAL\|GPU detected but driver"; then
        warn "dGPU power restored but NVIDIA driver won't bind."
        warn "Reboot to re-enable the dGPU."
    elif echo "$output" | grep -q "FAILED\|GPU not found"; then
        warn "dGPU did not reappear after power restoration."
        warn "Reboot required."
    else
        log "  $output"
    fi
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
            echo "  battery    Power off dGPU (eco, dgpu_disable=1, 0W)"
            echo "  ac         Restore dGPU power (standard, dgpu_disable=0)"
            echo "  status     Show current GPU power state"
            exit 1
            ;;
    esac
}

main "$@"
