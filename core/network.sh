#!/usr/bin/env bash
# =============================================================================
# network.sh — WiFi and Bluetooth power management
#
# Test independently:
#   sudo ./network.sh battery --dry-run
#   sudo ./network.sh ac --dry-run
#   ./network.sh status
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[network]"

WIFI_IFACE="${WIFI_IFACE:-wlan0}"

show_status() {
    echo "=== Network Power Status ==="
    
    # WiFi
    echo ""
    echo "WiFi ($WIFI_IFACE):"
    local wifi_ps
    wifi_ps=$(iw dev "$WIFI_IFACE" get power_save 2>/dev/null | awk '{print $NF}')
    echo "  Power-save: ${wifi_ps:-N/A}"
    
    local wifi_state
    wifi_state=$(cat /sys/class/net/"$WIFI_IFACE"/operstate 2>/dev/null)
    echo "  State: ${wifi_state:-N/A}"
    
    # Bluetooth
    echo ""
    echo "Bluetooth:"
    if command -v bluetoothctl &>/dev/null; then
        local bt_power
        bt_power=$(bluetoothctl show 2>/dev/null | grep -oP 'Powered: \K\w+')
        echo "  Powered: ${bt_power:-unknown}"
        
        local bt_discovering
        bt_discovering=$(bluetoothctl show 2>/dev/null | grep -oP 'Discovering: \K\w+')
        echo "  Discovering: ${bt_discovering:-unknown}"
    else
        echo "  bluetoothctl not found"
    fi
    
    # rfkill status
    echo ""
    echo "rfkill status:"
    rfkill list 2>/dev/null | head -20 || echo "  rfkill not available"
}

apply_battery() {
    require_root
    log "=== Applying battery network settings ==="
    
    # WiFi power-save
    log "--- WiFi ---"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] WiFi power_save → on"
    else
        if iw dev "$WIFI_IFACE" set power_save on 2>/dev/null; then
            log "  [ok] WiFi power_save → on"
        else
            warn "Failed to set WiFi power_save"
        fi
    fi

    # Bluetooth off
    log ""
    log "--- Bluetooth ---"
    if command -v bluetoothctl &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] Bluetooth → power off"
        else
            if bluetoothctl power off &>/dev/null; then
                log "  [ok] Bluetooth → power off"
            else
                warn "Failed to power off Bluetooth (may already be off)"
            fi
        fi
    else
        log "  [skip] bluetoothctl not found"
    fi
    
    log ""
    log "Battery network settings applied"
}

apply_ac() {
    require_root
    log "=== Applying AC network settings ==="
    
    # WiFi power-save off
    log "--- WiFi ---"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] WiFi power_save → off"
    else
        if iw dev "$WIFI_IFACE" set power_save off 2>/dev/null; then
            log "  [ok] WiFi power_save → off"
        else
            warn "Failed to unset WiFi power_save"
        fi
    fi

    # Bluetooth on
    log ""
    log "--- Bluetooth ---"
    if command -v bluetoothctl &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] Bluetooth → power on"
        else
            if bluetoothctl power on &>/dev/null; then
                log "  [ok] Bluetooth → power on"
            else
                warn "Failed to power on Bluetooth"
            fi
        fi
    else
        log "  [skip] bluetoothctl not found"
    fi
    
    log ""
    log "AC network settings applied"
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
            echo "  battery    WiFi power-save on, Bluetooth off"
            echo "  ac         WiFi power-save off, Bluetooth on"
            echo "  status     Show current network power settings"
            exit 1
            ;;
    esac
}

main "$@"
