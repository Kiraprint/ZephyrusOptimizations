#!/usr/bin/env bash
# =============================================================================
# power-monitor.sh — Auto-switch power profiles based on power source
#
# Logic:
#   - ACAD online (barrel charger) → AC mode (full performance)
#   - USB-C charging or battery    → Battery mode (power saving)
#   - GPU mode only changes at boot (runtime switch requires logout)
#
# Install:
#   sudo ./power-monitor.sh install
#
# Uninstall:
#   sudo ./power-monitor.sh uninstall
#
# Manual trigger (called by udev):
#   sudo ./power-monitor.sh switch
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POWER_SWITCH="$SCRIPT_DIR/power-switch.sh"
UDEV_RULE="/etc/udev/rules.d/99-zephyrus-power.rules"
SYSTEMD_SERVICE="/etc/systemd/system/zephyrus-power.service"
SUPERGFX_CONF="/etc/supergfxd.conf"
LOG_FILE="/var/log/zephyrus-power.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_power_source() {
    local acad_online
    acad_online=$(cat /sys/class/power_supply/ACAD/online 2>/dev/null || echo "0")
    
    if [[ "$acad_online" == "1" ]]; then
        echo "ac"
    else
        echo "battery"
    fi
}

do_switch() {
    local source
    source=$(get_power_source)
    
    log "Power source change detected → $source"
    
    if [[ -x "$POWER_SWITCH" ]]; then
        "$POWER_SWITCH" "$source" 2>&1 | while read -r line; do
            log "  $line"
        done
        log "Power profile applied: $source"
    else
        log "ERROR: power-switch.sh not found or not executable at $POWER_SWITCH"
        exit 1
    fi
}

do_boot() {
    local source
    source=$(get_power_source)
    
    log "Boot-time power setup → $source"
    
    # Set GPU mode based on power source (safe at boot, before user login)
    if [[ -f "$SUPERGFX_CONF" ]]; then
        local target_mode="Hybrid"
        [[ "$source" == "battery" ]] && target_mode="Integrated"
        
        local current_mode
        current_mode=$(grep -oP '"mode":\s*"\K[^"]+' "$SUPERGFX_CONF" 2>/dev/null || echo "unknown")
        
        if [[ "$current_mode" != "$target_mode" ]]; then
            sed -i "s/\"mode\":\s*\"[^\"]*\"/\"mode\": \"$target_mode\"/" "$SUPERGFX_CONF"
            log "  GPU mode config: $current_mode → $target_mode"
            # Restart supergfxd to apply (safe at boot, no user session yet)
            systemctl restart supergfxd 2>/dev/null || true
            sleep 2
        else
            log "  GPU mode already $target_mode"
        fi
    fi
    
    # Apply power profile
    if [[ -x "$POWER_SWITCH" ]]; then
        "$POWER_SWITCH" "$source" 2>&1 | while read -r line; do
            log "  $line"
        done
        log "Boot power profile applied: $source"
    else
        log "ERROR: power-switch.sh not found"
        exit 1
    fi
}

do_install() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: install requires root. Use: sudo $0 install" >&2
        exit 1
    fi
    
    echo "Installing Zephyrus power auto-switch..."
    
    # Create udev rule for plug/unplug events (CPU/power settings only, no GPU switching)
    cat > "$UDEV_RULE" << EOF
# Zephyrus G16 automatic power profile switching
# Triggers on AC adapter (barrel charger) state changes
# Note: GPU mode is NOT switched at runtime (requires logout)

ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="ACAD", \\
    RUN+="$SCRIPT_DIR/power-monitor.sh switch"
EOF
    
    echo "  Created: $UDEV_RULE"
    
    # Create systemd service for boot-time GPU mode + power profile
    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Zephyrus G16 Power Profile at Boot
After=supergfxd.service
Wants=supergfxd.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/power-monitor.sh boot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    echo "  Created: $SYSTEMD_SERVICE"
    
    # Reload udev rules
    udevadm control --reload-rules
    echo "  Reloaded udev rules"
    
    # Enable systemd service
    systemctl daemon-reload
    systemctl enable zephyrus-power.service
    echo "  Enabled systemd service (runs at boot)"
    
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    echo "  Log file: $LOG_FILE"
    
    echo ""
    echo "Installation complete!"
    echo "  - At boot: GPU mode set based on AC status (Integrated if battery, Hybrid if AC)"
    echo "  - At runtime: CPU/power settings switch when AC plugged/unplugged"
    echo "  - GPU mode does NOT switch at runtime (requires logout)"
    echo ""
    echo "To manually switch GPU mode:"
    echo "  supergfxctl -m Integrated   # (will logout)"
    echo "  supergfxctl -m Hybrid       # (will logout)"
    echo ""
    echo "View logs: tail -f $LOG_FILE"
}

do_uninstall() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: uninstall requires root. Use: sudo $0 uninstall" >&2
        exit 1
    fi
    
    echo "Uninstalling Zephyrus power auto-switch..."
    
    # Remove systemd service
    if [[ -f "$SYSTEMD_SERVICE" ]]; then
        systemctl disable zephyrus-power.service 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE"
        systemctl daemon-reload
        echo "  Removed: $SYSTEMD_SERVICE"
    else
        echo "  systemd service not found (already removed?)"
    fi
    
    # Remove udev rule
    if [[ -f "$UDEV_RULE" ]]; then
        rm -f "$UDEV_RULE"
        echo "  Removed: $UDEV_RULE"
        udevadm control --reload-rules
        echo "  Reloaded udev rules"
    else
        echo "  udev rule not found (already uninstalled?)"
    fi
    
    echo ""
    echo "Uninstallation complete."
}

show_status() {
    echo "=== Power Monitor Status ==="
    echo ""
    
    local source
    source=$(get_power_source)
    echo "Current power source: $source"
    echo ""
    
    echo "Power supplies:"
    for ps in /sys/class/power_supply/*; do
        local name type online
        name=$(basename "$ps")
        type=$(cat "$ps/type" 2>/dev/null || echo "?")
        online=$(cat "$ps/online" 2>/dev/null || echo "n/a")
        printf "  %-30s type=%-8s online=%s\n" "$name" "$type" "$online"
    done
    echo ""
    
    if [[ -f "$UDEV_RULE" ]]; then
        echo "udev rule: INSTALLED ($UDEV_RULE)"
    else
        echo "udev rule: NOT INSTALLED"
    fi
    
    if [[ -f "$SYSTEMD_SERVICE" ]]; then
        local svc_status
        svc_status=$(systemctl is-enabled zephyrus-power.service 2>/dev/null || echo "unknown")
        echo "systemd service: INSTALLED ($svc_status)"
    else
        echo "systemd service: NOT INSTALLED"
    fi
    
    # Check supergfxd
    if [[ -f "$SUPERGFX_CONF" ]]; then
        local default_mode
        default_mode=$(grep -oP '"mode":\s*"\K[^"]+' "$SUPERGFX_CONF" 2>/dev/null || echo "unknown")
        echo "supergfxd config mode: $default_mode"
        
        local current_mode
        current_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
        echo "supergfxctl current: $current_mode"
    fi
    
    # Check dGPU
    if [[ -d /sys/bus/pci/devices/0000:01:00.0 ]]; then
        echo "dGPU PCI: present"
    else
        echo "dGPU PCI: not present (powered off)"
    fi
    
    if [[ ! -f "$UDEV_RULE" ]] || [[ ! -f "$SYSTEMD_SERVICE" ]]; then
        echo ""
        echo "  Run: sudo $0 install"
    fi
    echo ""
    
    if [[ -f "$LOG_FILE" ]]; then
        echo "Recent log entries:"
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    fi
}

main() {
    local cmd="${1:-status}"
    
    case "$cmd" in
        switch)
            do_switch
            ;;
        boot)
            do_boot
            ;;
        install)
            do_install
            ;;
        uninstall)
            do_uninstall
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {switch|boot|install|uninstall|status}"
            echo ""
            echo "Commands:"
            echo "  switch      Apply power profile (CPU/power only, no GPU change)"
            echo "  boot        Boot-time setup (sets GPU mode + power profile)"
            echo "  install     Install udev rule and systemd service"
            echo "  uninstall   Remove udev rule and systemd service"
            echo "  status      Show current power monitor status"
            exit 1
            ;;
    esac
}

main "$@"
