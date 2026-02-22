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
    
    # PCIe ASPM
    log "--- PCIe ASPM ---"
    local aspm_policy="/sys/module/pcie_aspm/parameters/policy"
    if [[ -w "$aspm_policy" ]]; then
        sysfs_write "$aspm_policy" "powersupersave" "PCIe ASPM → powersupersave"
    else
        log "  [skip] PCIe ASPM: read-only (set via kernel cmdline pcie_aspm.policy=powersupersave)"
    fi

    log ""
    log "--- PCI Runtime PM → auto (excluding GPU) ---"
    for pci_ctrl in /sys/bus/pci/devices/*/power/control; do
        local pci_addr
        pci_addr=$(echo "$pci_ctrl" | grep -oP '0000:[0-9a-f:.]+')
        
        # Skip GPU slot to prevent D3cold wake issues with nvidia-open driver
        if [[ "$pci_addr" == "$GPU_PCI_ADDR" ]]; then
            sysfs_write "$pci_ctrl" "on" "  PCI $pci_addr (GPU) → on (D3cold protection)"
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
    
    # PCIe ASPM
    log "--- PCIe ASPM ---"
    local aspm_policy="/sys/module/pcie_aspm/parameters/policy"
    if [[ -w "$aspm_policy" ]]; then
        sysfs_write "$aspm_policy" "default" "PCIe ASPM → default"
    else
        log "  [skip] PCIe ASPM: read-only (set via kernel cmdline)"
    fi

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
    mode=$(parse_module_args "$@")
    
    case "$mode" in
        battery)  apply_battery ;;
        ac)       apply_ac ;;
        status)   show_status ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "  battery    ASPM powersupersave, runtime PM auto (GPU excluded)"
            echo "  ac         ASPM default, runtime PM on (all devices)"
            echo "  status     Show current PCI power settings"
            exit 1
            ;;
    esac
}

main "$@"
