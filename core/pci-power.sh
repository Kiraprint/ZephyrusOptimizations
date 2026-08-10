#!/usr/bin/env bash
# =============================================================================
# pci-power.sh — PCIe ASPM and PCI runtime power management
#
# Test independently:
#   sudo ./pci-power.sh battery --dry-run
#   sudo ./pci-power.sh ac --dry-run
#   ./pci-power.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[pci-power]"

GPU_PCI_ADDR="0000:01:00.0"
# Root port upstream of the dGPU. Excluded from runtime PM toggling too:
# putting it into 'auto' while the dGPU D3colds removes the whole subtree
# from the bus on this platform (ASUS EC cuts slot power).
GPU_PCI_BRIDGE="0000:00:01.0"

show_status() {
    echo "=== PCI Power Status ==="
    
    local aspm
    aspm=$(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null)
    echo "PCIe ASPM policy: $aspm"
    
    echo ""
    echo "PCI Runtime PM status (selected devices):"
    
    # Show key devices
    for dev in /sys/bus/pci/devices/0000:00:*/power/control /sys/bus/pci/devices/0000:01:*/power/control; do
        if [[ -f "$dev" ]]; then
            local addr
            addr=$(echo "$dev" | grep -oP '0000:[0-9a-f:.]+')
            local control
            control=$(cat "$dev" 2>/dev/null)
            local status
            status=$(cat "$(dirname "$dev")/runtime_status" 2>/dev/null || echo "?")
            printf "  %s: control=%s, status=%s\n" "$addr" "$control" "$status"
        fi
    done
    
    echo ""
    echo "GPU (RTX 5090) at $GPU_PCI_ADDR:"
    if [[ -f "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/control" ]]; then
        local gpu_ctrl
        gpu_ctrl=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/control" 2>/dev/null)
        local gpu_status
        gpu_status=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_status" 2>/dev/null)
        echo "  control: $gpu_ctrl"
        echo "  runtime_status: $gpu_status"
    else
        echo "  (not present)"
    fi
}

apply_battery() {
    require_root
    log "=== Applying battery PCI power settings ==="
    
    # ASPM policy is boot-time-only since kernel 7.1 (runtime sysfs interface
    # removed). Boot default comes from /etc/limine-entry-tool.d/aspm.conf.
    log "--- PCIe ASPM ---"
    log "  [info] policy: $(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null) (boot-time only)"

    log ""
    log "--- PCI Runtime PM → auto (excluding GPU) ---"
    for pci_ctrl in /sys/bus/pci/devices/*/power/control; do
        local pci_addr
        pci_addr=$(echo "$pci_ctrl" | grep -oP '0000:[0-9a-f:.]+')
        
        # Skip GPU + its root port — nvidia driver manages own PM; bridge
        # runtime-suspend with dGPU D3cold causes bus removal here
        if [[ "$pci_addr" == "$GPU_PCI_ADDR" || "$pci_addr" == "$GPU_PCI_BRIDGE" ]]; then
            log "  [skip] $pci_addr — GPU subtree (nvidia PM + platform D3cold quirk)"
        else
            sysfs_write "$pci_ctrl" "auto" "  PCI $pci_addr → auto"
        fi
    done
    
    log ""
    log "Battery PCI power settings applied"
}

apply_ac() {
    require_root
    log "=== Applying AC PCI power settings ==="
    
    log "--- PCIe ASPM ---"
    log "  [info] policy: $(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null) (boot-time only)"

    log ""
    log "--- PCI Runtime PM → on (lowest latency) ---"
    for pci_ctrl in /sys/bus/pci/devices/*/power/control; do
        local pci_addr
        pci_addr=$(echo "$pci_ctrl" | grep -oP '0000:[0-9a-f:.]+')
        sysfs_write "$pci_ctrl" "on" "  PCI $pci_addr → on"
    done
    
    log ""
    log "AC PCI power settings applied"
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
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "  battery    Runtime PM auto (GPU excluded)"
            echo "  ac         Runtime PM on (all devices)"
            echo "  status     Show current PCI power settings"
            exit 1
            ;;
    esac
}

main "$@"
