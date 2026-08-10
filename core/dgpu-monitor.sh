#!/usr/bin/env bash
# dgpu-monitor.sh — log everything about dGPU power/presence transitions.
#
# Modes:
#   event <add|remove>   — called by udev on dGPU add/remove (full state dump)
#   watch                — loop; dumps full state whenever anything changes
#   status               — one-shot current state
#
# Log: /var/log/zephyrus-dgpu.log
#
# Also enables the kernel pci_power_state tracepoint so we can see whether
# the PCI core ever commands D3cold on the dGPU/bridge before the platform
# removes the device (or whether the removal is purely EC/firmware-side).
set -uo pipefail

LOG=/var/log/zephyrus-dgpu.log
GPU=0000:01:00.0
BRIDGE=0000:00:01.0
TRACE_BASE=""
[[ -r /sys/kernel/tracing/trace ]] && TRACE_BASE=/sys/kernel/tracing
[[ -z "$TRACE_BASE" && -r /sys/kernel/debug/tracing/trace ]] && TRACE_BASE=/sys/kernel/debug/tracing

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

ac() { cat /sys/class/power_supply/ACAD/online 2>/dev/null || echo "?"; }

present() { [[ -d "/sys/bus/pci/devices/$GPU" ]] && echo yes || echo no; }

draw() {
    awk -v i="$(cat /sys/class/power_supply/BAT1/current_now 2>/dev/null)" \
        -v v="$(cat /sys/class/power_supply/BAT1/voltage_now 2>/dev/null)" \
        'BEGIN { if (i+0 > 0 && v+0 > 0) printf "%.1f", i*v/1e12; else print "?" }'
}

dump_state() {
    local reason="$1"
    log "=== $reason ==="
    log "  AC: $(ac) | GPU on bus: $(present) | total draw: $(draw)W"
    if [[ -d "/sys/bus/pci/devices/$GPU" ]]; then
        log "  GPU  power_state=$(cat /sys/bus/pci/devices/$GPU/power_state 2>/dev/null) runtime=$(cat /sys/bus/pci/devices/$GPU/power/runtime_status 2>/dev/null) control=$(cat /sys/bus/pci/devices/$GPU/power/control 2>/dev/null)"
        log "  BRIDGE control=$(cat /sys/bus/pci/devices/$BRIDGE/power/control 2>/dev/null) power_state=$(cat /sys/bus/pci/devices/$BRIDGE/power_state 2>/dev/null)"
    fi
    log "  driver: $(cat /proc/driver/nvidia/gpus/$GPU/power 2>/dev/null | grep -E 'Runtime D3|Video Memory|S0ix' | tr '\n' '|')"
    log "  cardwire: $(cardwire get 2>/dev/null | head -1) | lsof: $(cardwire gpu 1 --lsof 2>/dev/null | tr '\n' ' ')"
    log "  nvidia-powerd: $(systemctl is-active nvidia-powerd 2>/dev/null)"
    local smi
    smi=$(nvidia-smi --query-gpu=name,temperature.gpu,power.draw,utilization.gpu,clocks.current.graphics --format=csv,noheader 2>/dev/null)
    log "  nvidia-smi: ${smi:-n/a}"
    if [[ -n "$TRACE_BASE" ]]; then
        log "  kernel pci_power_state (last 4): $(grep 'pci_power_state' "$TRACE_BASE/trace" 2>/dev/null | tail -4 | tr '\n' '|')"
    fi
}

enable_trace() {
    if [[ -n "$TRACE_BASE" && -w "$TRACE_BASE/events/power/pci_power_state/enable" ]]; then
        echo 1 > "$TRACE_BASE/events/power/pci_power_state/enable" 2>/dev/null
    fi
}

case "${1:-status}" in
    event)
        enable_trace
        dump_state "udev-event: dGPU ${2:-changed}"
        ;;
    watch)
        enable_trace
        log "=== watcher started (pid $$) ==="
        last=""
        while true; do
            now="$(ac)|$(present)|$(draw)|$(cardwire get 2>/dev/null | head -1)"
            if [[ "$now" != "$last" ]]; then
                dump_state "change detected"
                last="$now"
            fi
            sleep 5
        done
        ;;
    *)
        dump_state "status"
        ;;
esac
