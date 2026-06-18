#!/usr/bin/env bash
# =============================================================================
# kernel-tunables.sh — Kernel power tunables (NMI, VM writeback, etc.)
#
# Test independently:
#   sudo ./kernel-tunables.sh battery --dry-run
#   sudo ./kernel-tunables.sh ac --dry-run
#   ./kernel-tunables.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[kernel]"

show_status() {
    echo "=== Kernel Tunables Status ==="
    
    local nmi
    nmi=$(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null)
    echo "NMI watchdog    : $nmi"

    local writeback
    writeback=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null)
    echo "VM writeback    : ${writeback}cs ($((writeback / 100))s)"
    
    local expire
    expire=$(cat /proc/sys/vm/dirty_expire_centisecs 2>/dev/null)
    echo "Dirty expire    : ${expire}cs"
    
    local ratio
    ratio=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null)
    echo "Dirty ratio     : ${ratio}%"
    
    # NVMe scheduler
    echo ""
    echo "NVMe I/O schedulers:"
    for sched in /sys/block/nvme*/queue/scheduler; do
        if [[ -f "$sched" ]]; then
            local dev
            dev=$(echo "$sched" | grep -oP 'nvme[0-9]+')
            local current
            current=$(cat "$sched" 2>/dev/null)
            echo "  $dev: $current"
        fi
    done
}

apply_battery() {
    require_root
    log "=== Applying battery kernel tunables ==="
    
    sysfs_write "/proc/sys/kernel/nmi_watchdog" "0" "NMI watchdog → off"
    sysfs_write "/proc/sys/vm/dirty_writeback_centisecs" "1500" "VM writeback → 1500cs (15s)"
    
    log ""
    log "Battery kernel tunables applied"
}

apply_ac() {
    require_root
    log "=== Applying AC kernel tunables ==="
    
    sysfs_write "/proc/sys/kernel/nmi_watchdog" "1" "NMI watchdog → on"
    sysfs_write "/proc/sys/vm/dirty_writeback_centisecs" "500" "VM writeback → 500cs (5s)"
    
    log ""
    log "--- NVMe I/O scheduler ---"
    for nvme_sched in /sys/block/nvme*/queue/scheduler; do
        local nvme_dev
        nvme_dev=$(echo "$nvme_sched" | grep -oP 'nvme[0-9]+')
        sysfs_write "$nvme_sched" "none" "  $nvme_dev scheduler → none"
    done
    
    log ""
    log "AC kernel tunables applied"
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
            echo "  battery    NMI off, writeback 15s"
            echo "  ac         NMI on, writeback 5s, NVMe scheduler=none"
            echo "  status     Show current kernel tunables"
            exit 1
            ;;
    esac
}

main "$@"
