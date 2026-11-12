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

# PCIe bridge upstream of dGPU — used for Secondary Bus Reset recovery
# when the GPU is stuck (fallen off the bus, GSP crash). Only reachable on
# AC while the rail is on: cardwire hides 0000:00:01.0 in integrated mode.
GPU_PCI_BRIDGE="0000:00:01.0"
SETPCI_CMD="/usr/bin/setpci"


# --- NVIDIA module unloading (for clean suspend with dGPU off) ---------------
NVIDIA_MODULES=("nvidia_drm" "nvidia_modeset" "nvidia_uvm" "nvidia" "nvidia_wmi_ec_backlight")

unload_nvidia_modules() {
    log "  Unloading NVIDIA kernel modules for clean suspend..."
    local failed=0
    for mod in "${NVIDIA_MODULES[@]}"; do
        if lsmod | grep -q "^${mod} "; then
            if modprobe -r "$mod" 2>/dev/null; then
                log "    [ok] $mod unloaded"
            else
                log "    [skip] $mod still in use (processes hold it)"
                failed=1
            fi
        fi
    done
    if [[ "$failed" -eq 0 ]]; then
        log "  [ok] All NVIDIA modules unloaded — DRM subsystem freed"
    else
        log "  [warn] Some modules still loaded — suspend may still fail"
        log "  [hint] Log out or close apps using libnvidia-*.so"
    fi
}

load_nvidia_modules() {
    log "  Loading NVIDIA kernel modules..."
    if modprobe nvidia_drm 2>/dev/null; then
        log "    [ok] NVIDIA modules loaded"
    else
        log "    [warn] NVIDIA modules failed to load — reboot may be needed"
    fi
}

disable_nvidia_services() {
    log "  Disabling NVIDIA services (dGPU is off)..."
    systemctl disable --now nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null
    systemctl disable --now nvidia-powerd.service 2>/dev/null
    log "    [ok] nvidia-suspend/resume/hibernate/powerd → disabled"
}

enable_nvidia_services() {
    log "  Enabling NVIDIA services (dGPU is on)..."
    systemctl enable --now nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null
    systemctl enable --now nvidia-powerd.service 2>/dev/null
    log "    [ok] nvidia-suspend/resume/hibernate/powerd → enabled"
}
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

# --- PCIe bridge recovery -------------------------------------------------------
_pcie_bridge_sbr() {
    log "  Attempting PCIe Secondary Bus Reset on bridge $GPU_PCI_BRIDGE..."

    if [[ $EUID -ne 0 ]]; then
        warn "  SBR needs root (setpci writes bridge config space)"
        return 1
    fi

    if [[ ! -x "$SETPCI_CMD" ]]; then
        warn "  setpci not found — install pciutils for SBR recovery"
        return 1
    fi

    if [[ ! -d "/sys/bus/pci/devices/$GPU_PCI_BRIDGE" ]]; then
        warn "  Bridge $GPU_PCI_BRIDGE not found — cannot reset"
        return 1
    fi

    # Log current link state before reset
    local link_status
    link_status=$(setpci -s "$GPU_PCI_BRIDGE" CAP_EXP+0x12.w 2>/dev/null || echo "unknown")
    log "  Pre-reset link status: $link_status"

    # Set Secondary Bus Reset bit (bit 6) in Bridge Control register
    # This forces the downstream device to retrain PCIe link
    if ! $SETPCI_CMD -s "$GPU_PCI_BRIDGE" BRIDGE_CONTROL.w=0x40 2>/dev/null; then
        warn "  SBR failed — bridge may be locked"
        return 1
    fi

    sleep 1

    # Clear SBR bit
    $SETPCI_CMD -s "$GPU_PCI_BRIDGE" BRIDGE_CONTROL.w=0x00 2>/dev/null || true

    sleep 2

    # Rescan the bridge to re-enumerate downstream devices
    if [[ -w "/sys/bus/pci/devices/$GPU_PCI_BRIDGE/rescan" ]]; then
        echo 1 > "/sys/bus/pci/devices/$GPU_PCI_BRIDGE/rescan" 2>/dev/null || true
    fi

    sleep 1

    # Check if GPU reappeared
    if [[ -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
        log "  GPU reappeared after SBR"
        return 0
    else
        warn "  GPU did not reappear after SBR"
        return 1
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

    # GPU may already be gone from the bus (D3cold removal on this platform).
    # eco still applies: dgpu_disable=1 persists in the EC and gives a clean
    # boot next time (dGPU never enumerated -> no driver, no zombie).
    if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]] || \
       ! cat "/sys/bus/pci/devices/0000:01:00.0/vendor" &>/dev/null; then
        warn "GPU not present on the bus (D3cold removal) — eco still applied for next boot"
    fi

    # cardwired holds /dev/nvidia* open itself — dgpu-switch eco aborts while
    # any handle exists ("ERROR: NVIDIA in use", blocker: cardwired). Order:
    # integrated first (needs daemon + device), then stop the daemon so the
    # rail cut can proceed. Daemon is restarted after eco below.
    cardwire_set_mode "integrated"

    if systemctl is-active --quiet cardwired 2>/dev/null; then
        log "  Stopping cardwired before rail cut (holds /dev/nvidia* open)"
        systemctl stop cardwired 2>/dev/null || true
        sleep 1
    fi

    # Close GPU clients that hold /dev/nvidia* open — they make dgpu-switch
    # abort with "ERROR: NVIDIA in use" and the rail never gets cut (observed:
    # Mission Center keeps 15 fds on /dev/nvidia0 via NVML, 64Gram holds the
    # device mapped with zero active contexts — invisible in nvtop). Stop
    # nvidia-powerd too so module unload succeeds afterwards.
    local holders
    holders=$(pgrep -f 'missioncenter|missioncenter-m' 2>/dev/null) || true
    if [[ -n "$holders" ]]; then
        log "  Stopping GPU monitor (holds /dev/nvidia* open): missioncenter"
        pkill -f 'missioncenter' 2>/dev/null || true
        sleep 1
    fi
    # Any other process with the device mapped pins the rail even when idle
    # (nvtop shows no utilization for mapped-but-idle clients). Report them
    # instead of aborting blindly.
    local mapped
    mapped=$(fuser /dev/nvidia0 /dev/nvidiactl 2>/dev/null | grep -oP '\d+' | sort -u || true)
    if [[ -n "$mapped" ]]; then
        log "  Processes with /dev/nvidia* mapped:"
        echo "$mapped" | while read -r pid; do
            log "    $pid $(ps -p "$pid" -o comm= 2>/dev/null)"
        done
    fi
    if systemctl is-active --quiet nvidia-powerd 2>/dev/null; then
        log "  Stopping nvidia-powerd before rail cut"
        systemctl stop nvidia-powerd 2>/dev/null || true
    fi

    # Run eco mode — will fail gracefully if NVIDIA is in use
    local output
    output=$(timeout "$DGPU_TIMEOUT" "$DGPU_SWITCH" eco 2>&1) || true

    # Rail cut done (or device already gone) — bring cardwired back so the
    # daemon stays managed. NOTE: with the device rail-off cardwire reports
    # hybrid and refuses `set integrated` (no offload dGPU present); harmless —
    # there is nothing to route until the device re-enumerates on AC.
    if systemctl is-enabled --quiet cardwired 2>/dev/null; then
        systemctl start cardwired 2>/dev/null || true
    fi

    if echo "$output" | grep -q "ERROR: NVIDIA in use"; then
        warn "dGPU is in use by user processes — cannot power off."
        warn "Log out first, then unplug AC again, or run manually:"
        warn "  sudo dgpu-switch.sh eco"
        warn ""
        warn "Processes blocking dGPU power-off:"
        echo "$output" | grep -E "^\s+[A-Z]"
        return 1
    fi

    if echo "$output" | grep -q "Eco\|Confirmed\|ECO"; then
        log "  [ok] dGPU powered off (dgpu_disable=1, 0W)"
    else
        log "  $output"
    fi

    # dGPU is now powered off — unload NVIDIA kernel modules to free DRM
    # so KWin doesn't block suspend with "atomic commit failed: Device or resource busy"
    unload_nvidia_modules

    # Disable NVIDIA suspend services — no point with dGPU off
    disable_nvidia_services
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
        # Recovery attempt: the link may be down but the rail is now powered,
        # so a Secondary Bus Reset can force retraining + re-enumeration.
        if _pcie_bridge_sbr; then
            if ! lsmod | grep -q "^nvidia "; then
                load_nvidia_modules
            fi
            if lsmod | grep -q "^nvidia "; then
                log "  [ok] driver rebound after SBR"
            else
                warn "GPU visible but driver did not bind. Reboot required."
            fi
        else
            warn "Reboot required."
        fi
    fi

    # dGPU is back — reload NVIDIA modules if they were unloaded
    if ! lsmod | grep -q "^nvidia "; then
        load_nvidia_modules
    fi

    # Re-enable NVIDIA suspend services — dGPU is on
    enable_nvidia_services
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
        recover)  _pcie_bridge_sbr ;;
        *)
            echo "Usage: $0 {battery|ac|status|recover} [--dry-run]"
            echo "  battery    Power off dGPU (eco, dgpu_disable=1, 0W)"
            echo "  ac         Restore dGPU power (standard, dgpu_disable=0)"
            echo "  status     Show current GPU power state"
            echo "  recover    PCIe Secondary Bus Reset on the dGPU bridge (AC only)"
            exit 1
            ;;
    esac
}

main "$@"
