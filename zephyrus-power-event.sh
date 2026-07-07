#!/usr/bin/env bash
# =============================================================================
# zephyrus-power-event — Udev power event handler
#
# Called by udev when AC adapter is plugged/unplugged.
# Extracts the user's desktop session environment so DE detection and display
# refresh-rate switching work correctly when running as root.
#
# Install to: /usr/local/bin/zephyrus-power-event
# Make executable: chmod +x /usr/local/bin/zephyrus-power-event
# =============================================================================

set -euo pipefail

POWER_SCRIPT="/home/kir/Code/ZephyrusOptimizations/power-switch-unified.sh"
LOG_FILE="/var/log/zephyrus-power.log"
DISPLAY_USER="kir"

AC_ONLINE="${1:-unknown}"

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

MODE=""
if [[ "$AC_ONLINE" == "1" ]]; then
    MODE="ac"
elif [[ "$AC_ONLINE" == "0" ]]; then
    MODE="battery"
else
    log_event "ERROR: Unknown power state: $AC_ONLINE"
    exit 1
fi

log_event "${MODE} - dispatching ${MODE}"

# Extract desktop session environment from the running display session.
# systemd-run (root) doesn't inherit XDG_CURRENT_DESKTOP, DBUS, WAYLAND etc.
# We pluck them from the running compositor and set them via --setenv.
ENV_FLAGS=()
desktop_pid=""

for proc in plasmashell gnome-shell Xwayland; do
    desktop_pid=$(pgrep -u "$DISPLAY_USER" -x "$proc" 2>/dev/null | head -1)
    [[ -n "$desktop_pid" ]] && break
done

if [[ -n "$desktop_pid" ]] && [[ -r "/proc/$desktop_pid/environ" ]]; then
    while IFS='=' read -r key val; do
        case "$key" in
            XDG_CURRENT_DESKTOP|WAYLAND_DISPLAY|DISPLAY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)
                ENV_FLAGS+=(--setenv="$key=$val")
                ;;
        esac
    done < <(tr '\0' '\n' < "/proc/$desktop_pid/environ")
    log_event "detected desktop session (pid=$desktop_pid)"
else
    log_event "WARNING: no desktop session, display switching will be skipped"
fi

log_event "Running: systemd-run power-switch-unified.sh ${MODE}"
log_event "  env: XDG_CURRENT_DESKTOP=$(echo "${ENV_FLAGS[@]}" | grep -o 'XDG_CURRENT_DESKTOP=[^ ]*' || echo '(not set)')"

systemd-run --no-block \
    --unit="zephyrus-power-${MODE}-$$" \
    --description="Zephyrus G16 Power Switch (${MODE})" \
    --collect \
    "${ENV_FLAGS[@]}" \
    "$POWER_SCRIPT" "$MODE" >> "$LOG_FILE" 2>&1
