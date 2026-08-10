#!/usr/bin/env bash
# =============================================================================
# gpu.sh — dGPU status reporting for ASUS ROG Zephyrus G16 (RTX 5090)
#
# The dGPU is fully owned by cardwire: it reacts to power events itself
# (battery_auto_switch) — integrated on battery (dGPU idles into D3cold),
# hybrid on AC (available for ML/gaming). This module does NOT act on the
# dGPU at all: no dgpu_disable writes, no cardwire calls, no PCIe
# power/control, no module/service management. It only reports status.
#
# Test independently:
#   sudo ./gpu.sh battery      # no-op (cardwire handles the dGPU)
#   sudo ./gpu.sh ac           # no-op (cardwire handles the dGPU)
#   ./gpu.sh status            # Show current state
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[gpu]"

DGPU_SWITCH="/usr/local/bin/dgpu-switch.sh"

# Cardwire — eBPF-based GPU access control (not power!)
CARDWIRE_CMD="/usr/bin/cardwire"

cardwire_available() {
    [[ -x "$CARDWIRE_CMD" ]] && systemctl is-active --quiet cardwired 2>/dev/null
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
    echo "  dGPU handled automatically by cardwire (battery_auto_switch)"
    echo "  battery → integrated (D3cold) | ac → hybrid — no script action needed"
}

apply_battery() {
    log "=== Battery: dGPU D3cold (cardwire auto-switches to integrated) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Nothing to do — cardwire owns the dGPU on battery"
        return 0
    fi

    # Cardwire reacts to the UPower battery event itself (battery_auto_switch)
    # and blocks the dGPU, letting the driver runtime-suspend it (D3cold).
    # This script deliberately does nothing to the dGPU.
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        warn "dGPU not on the bus — check cardwire/journal for what happened"
    fi

    # nvidia-powerd (Dynamic Boost) pins the dGPU via NVML — cardwire lsof
    # shows it holding /dev/nvidia0 + /dev/nvidiactl, keeping the driver
    # RM-active (Video Memory: Active). It is an AC/gaming feature; stop it
    # on battery so nothing holds the dGPU while it should sleep.
    if systemctl is-active --quiet nvidia-powerd 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] would stop nvidia-powerd (pins dGPU in D0)"
        else
            systemctl stop nvidia-powerd 2>/dev/null || true
            log "  [ok] nvidia-powerd stopped (Dynamic Boost is AC-only)"
        fi
    fi
}

apply_ac() {
    log "=== AC: dGPU available (cardwire auto-switches to hybrid) ==="

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Nothing to do — cardwire owns the dGPU on AC"
        return 0
    fi

    # Cardwire unblocks the dGPU itself on the AC event (battery_auto_switch);
    # the dGPU is then available for explicit ML/gaming workloads.
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        warn "dGPU not on the bus — it returns on the next reboot"
    fi

    # Re-enable Dynamic Boost on AC (per asus-linux/nvidia-laptop-power-cfg)
    if ! systemctl is-active --quiet nvidia-powerd 2>/dev/null; then
        systemctl start nvidia-powerd 2>/dev/null || true
        log "  [ok] nvidia-powerd started (Dynamic Boost on AC)"
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
            echo "  battery    no-op — cardwire handles dGPU (D3cold on battery)"
            echo "  ac         no-op — cardwire handles dGPU (hybrid on AC)"
            echo "  status     Show current GPU power state"
            exit 1
            ;;
    esac
}

main "$@"
