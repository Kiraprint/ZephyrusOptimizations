#!/usr/bin/env bash
# =============================================================================
# nvme-power.sh — NVMe power management for unused drives
#
# Disables/enables NVMe drives to save power. Useful for Windows dual-boot
# drives that are never accessed from Linux.
#
# Test independently:
#   sudo ./nvme-power.sh status
#   sudo ./nvme-power.sh battery --dry-run
#   sudo ./nvme-power.sh battery
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[nvme-power]"

WINDOWS_DISK_PATTERN="MTFDKBA1T0QGN"

get_nvme_devices() {
    for dev in /sys/class/nvme/nvme*/model; do
        local nvme_name
        nvme_name=$(basename "$(dirname "$dev")")
        local model
        model=$(cat "$dev" 2>/dev/null)
        echo "$nvme_name:$model"
    done
}

get_windows_nvme() {
    get_nvme_devices | grep -F "$WINDOWS_DISK_PATTERN" | cut -d: -f1
}

show_status() {
    echo "=== NVMe Power Status ==="
    echo ""
    
    while IFS=: read -r nvme_name model; do
        local pci_path="/sys/class/nvme/$nvme_name/device"
        local control=""
        local runtime_status=""
        local is_windows=""
        
        if [[ -f "$pci_path/power/control" ]]; then
            control=$(cat "$pci_path/power/control" 2>/dev/null || echo "unknown")
        else
            control="not available"
        fi
        
        if [[ -f "$pci_path/power/runtime_status" ]]; then
            runtime_status=$(cat "$pci_path/power/runtime_status" 2>/dev/null || echo "unknown")
        else
            runtime_status="not available"
        fi
        
        if echo "$model" | grep -qF "$WINDOWS_DISK_PATTERN"; then
            is_windows=" (Windows disk)"
        fi
        
        echo "$nvme_name: $model$is_windows"
        echo "  Control: $control"
        echo "  Runtime status: $runtime_status"
        
        local enabled=""
        if [[ -f "$pci_path/enable" ]]; then
            enabled=$(cat "$pci_path/enable" 2>/dev/null)
            echo "  PCI enabled: $enabled"
        fi
        
        echo ""
    done < <(get_nvme_devices)
    
    local win_nvme
    win_nvme=$(get_windows_nvme)
    if [[ -n "$win_nvme" ]]; then
        echo "Windows disk detected: $win_nvme"
        echo "Recommend disabling on battery to save 0.5-2W"
    else
        echo "No Windows disk detected (pattern: $WINDOWS_DISK_PATTERN)"
    fi
}

disable_windows_nvme() {
    local win_nvme
    win_nvme=$(get_windows_nvme)
    
    if [[ -z "$win_nvme" ]]; then
        log "  [skip] No Windows disk found (pattern: $WINDOWS_DISK_PATTERN)"
        return 0
    fi
    
    local pci_path="/sys/class/nvme/$win_nvme/device"
    local remove_path="$pci_path/remove"
    
    if [[ ! -f "$remove_path" ]]; then
        warn "Cannot find PCI remove path for $win_nvme"
        return 1
    fi
    
    log "Disabling Windows NVMe disk: $win_nvme"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would write 1 to $remove_path"
        log "  [dry-run] This removes the device from PCI bus (can be rescanned)"
        return 0
    fi
    
    local model
    model=$(cat "/sys/class/nvme/$win_nvme/model" 2>/dev/null || echo "unknown")
    log "  Model: $model"
    log "  Action: Removing from PCI bus"
    
    if echo 1 > "$remove_path" 2>/dev/null; then
        log "  [ok] $win_nvme disabled (removed from PCI bus)"
        log "  Power saving: ~0.5-2W"
    else
        warn "Failed to disable $win_nvme"
        return 1
    fi
}

enable_windows_nvme() {
    local win_nvme
    win_nvme=$(get_windows_nvme)
    
    if [[ -n "$win_nvme" ]]; then
        log "  [skip] Windows disk already present: $win_nvme"
        return 0
    fi
    
    log "Re-scanning PCI bus to enable Windows NVMe disk"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would rescan PCI bus"
        return 0
    fi
    
    local pci_rescan="/sys/bus/pci/rescan"
    
    if [[ ! -f "$pci_rescan" ]]; then
        warn "PCI rescan not available"
        return 1
    fi
    
    if echo 1 > "$pci_rescan" 2>/dev/null; then
        sleep 1
        
        win_nvme=$(get_windows_nvme)
        if [[ -n "$win_nvme" ]]; then
            log "  [ok] Windows disk re-enabled: $win_nvme"
        else
            log "  [ok] PCI rescan completed (disk may take a moment to appear)"
        fi
    else
        warn "Failed to rescan PCI bus"
        return 1
    fi
}

apply_battery() {
    require_root
    log "=== Applying battery NVMe power settings ==="
    log ""
    
    disable_windows_nvme || true
    
    log ""
    log "Battery NVMe power settings applied"
}

apply_ac() {
    require_root
    log "=== Applying AC NVMe power settings ==="
    log ""
    
    enable_windows_nvme || true
    
    log ""
    log "AC NVMe power settings applied"
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
            echo "  battery    Disable Windows NVMe disk to save power (~0.5-2W)"
            echo "  ac         Re-enable Windows NVMe disk"
            echo "  status     Show current NVMe power states"
            echo ""
            echo "This script removes unused NVMe drives from the PCI bus on battery"
            echo "and rescans the bus on AC to make them available again."
            echo ""
            echo "Current Windows disk pattern: $WINDOWS_DISK_PATTERN"
            exit 1
            ;;
    esac
}

main "$@"
