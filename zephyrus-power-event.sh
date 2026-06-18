#!/usr/bin/env bash
# =============================================================================
# zephyrus-power-event — Udev power event handler
#
# Called by udev when AC adapter is plugged/unplugged.
# Uses systemd-run to avoid udev's short timeout.
# Triggers power-switch-unified.sh to apply battery/AC optimizations.
#
# Install to: /usr/local/bin/zephyrus-power-event
# Make executable: chmod +x /usr/local/bin/zephyrus-power-event
# =============================================================================

set -euo pipefail

POWER_SCRIPT="/home/kir/Code/ZephyrusOptimizations/power-switch-unified.sh"
LOG_FILE="/var/log/zephyrus-power.log"

# $1 = POWER_SUPPLY_ONLINE (1 = AC connected, 0 = on battery)
AC_ONLINE="${1:-unknown}"

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

MODE=""
if [[ "$AC_ONLINE" == "1" ]]; then
    MODE="ac"
    log_event "AC connected - dispatching $MODE"
elif [[ "$AC_ONLINE" == "0" ]]; then
    MODE="battery"
    log_event "Battery mode - dispatching $MODE"
else
    log_event "Unknown power state: $AC_ONLINE"
    exit 1
fi

# Run via systemd-run to escape udev's short timeout
# Uses system-level unit (no --user) — display module handles user detection
log_event "Running: systemd-run power-switch-unified.sh $MODE"
systemd-run --no-block --unit="zephyrus-power-${MODE}" \
    --description="Zephyrus G16 Power Switch ($MODE)" \
    --collect \
    "$POWER_SCRIPT" "$MODE" >> "$LOG_FILE" 2>&1
