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
    
    # CPU scheduler (EEVDF default, scx_lavd on AC)
    # /sys/kernel/sched_ext/state is unreliable on rc kernels — check the
    # systemd unit instead.
    if systemctl is-active --quiet zephyrus-scx-lavd.service 2>/dev/null; then
        echo "CPU scheduler   : scx_lavd (sched-ext, performance)"
    else
        echo "CPU scheduler   : EEVDF (kernel default)"
    fi

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
    
    # Back to EEVDF: stop scx_lavd if it was loaded for AC gaming
    if systemctl is-active --quiet zephyrus-scx-lavd.service 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] would stop zephyrus-scx-lavd.service (→ EEVDF)"
        else
            # systemctl stop sends SIGTERM and waits for the graceful BPF
            # unload to finish (TimeoutStopSec=15 in the unit).
            systemctl stop zephyrus-scx-lavd.service
            log "  [ok] unloaded scx_lavd (→ EEVDF)"
        fi
    else
        log "  [skip] scx_lavd not loaded (EEVDF already active)"
    fi
    
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
    # kyber: latency-focused, low CPU overhead; bounds P99 latency under
    # mixed load (game reads + shader-cache/Steam writes). 'none' is fine on
    # battery (left untouched there) but gives no latency bounding while gaming.
    for nvme_sched in /sys/block/nvme*/queue/scheduler; do
        local nvme_dev
        nvme_dev=$(echo "$nvme_sched" | grep -oP 'nvme[0-9]+')
        sysfs_write "$nvme_sched" "kyber" "  $nvme_dev scheduler → kyber"
    done
    
    log ""
    log "--- CPU scheduler ---"
    # scx_lavd: Valve's latency-aware scheduler (SteamOS default for gaming).
    # Improves 1% lows / reduces stutter vs EEVDF; unloaded again on battery.
    # Runs as its own systemd unit (zephyrus-scx-lavd.service): backgrounding
    # inside the systemd-run transient unit gets cgroup-reaped on exit.
    if systemctl is-active --quiet zephyrus-scx-lavd.service 2>/dev/null; then
        log "  [skip] scx_lavd already running"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] would start zephyrus-scx-lavd.service (scx_lavd --performance)"
    else
        if [[ -f /usr/lib/systemd/system/zephyrus-scx-lavd.service ]] || [[ -f /etc/systemd/system/zephyrus-scx-lavd.service ]]; then
            if systemctl start zephyrus-scx-lavd.service 2>/dev/null; then
                log "  [ok] scx_lavd --performance loaded"
            else
                warn "scx_lavd failed to start (systemctl start returned non-zero)"
            fi
        else
            warn "zephyrus-scx-lavd.service not installed — run install-udev-autoswitching.sh"
        fi
    fi
    
    log ""
    log "AC kernel tunables applied"
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
            echo "  battery    NMI off, writeback 15s"
            echo "  ac         NMI on, writeback 5s, NVMe scheduler=none"
            echo "  status     Show current kernel tunables"
            exit 1
            ;;
    esac
}

main "$@"
