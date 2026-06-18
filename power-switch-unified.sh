#!/usr/bin/env bash
# =============================================================================
# power-switch-unified.sh — Multi-DE power management for ASUS ROG Zephyrus G16
#
# Supports: GNOME, KDE Plasma
#
# Usage:
#   sudo ./power-switch-unified.sh battery      # Apply battery optimizations
#   sudo ./power-switch-unified.sh ac           # Apply AC / beast mode
#   sudo ./power-switch-unified.sh status       # Show current state (no root needed)
#   sudo ./power-switch-unified.sh battery --dry-run   # Preview without applying
#   sudo ./power-switch-unified.sh ac --dry-run        # Preview without applying
#
# Architecture:
#   - Core modules: DE-agnostic (CPU, GPU, network, audio, etc.)
#   - DE modules: Desktop-specific (display, effects/extensions)
#   - Auto-detects current DE and loads appropriate modules
#
# Safety:
#   - CPU 0 is NEVER offlined
#   - All changes are reversible via the opposite mode
#   - --dry-run previews every change before applying
#   - Every write to sysfs checks the path exists first
#   - USB autosuspend skips HID devices (keyboard/mouse)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration -----------------------------------------------------------
export DRY_RUN=false
export LOG_PREFIX="[power-switch]"
export WIFI_IFACE="wlan0"
export AC_SUPPLY="/sys/class/power_supply/ACAD/online"

# --- Helpers -----------------------------------------------------------------
source "$SCRIPT_DIR/core/common.sh"

# --- DE Detection ------------------------------------------------------------
detect_desktop_environment() {
    # Check XDG_CURRENT_DESKTOP first
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
            echo "gnome"
            return 0
        elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
            echo "kde"
            return 0
        fi
    fi
    
    # Fallback: check running processes
    if pgrep -x gnome-shell >/dev/null 2>&1; then
        echo "gnome"
        return 0
    elif pgrep -x plasmashell >/dev/null 2>&1; then
        echo "kde"
        return 0
    fi
    
    echo "unknown"
}

# --- Load DE-Specific Modules ------------------------------------------------
load_de_modules() {
    local de="$1"
    
    case "$de" in
        gnome)
            DE_DISPLAY="$SCRIPT_DIR/de/gnome/display.sh"
            DE_VISUAL="$SCRIPT_DIR/de/gnome/extensions.sh"
            DE_SERVICES=""  # GNOME doesn't need service management
            DE_COMPOSITOR_GPU=""  # GNOME doesn't support this easily
            log "Detected Desktop Environment: GNOME"
            ;;
        kde)
            DE_DISPLAY="$SCRIPT_DIR/de/kde/display.sh"
            DE_VISUAL="$SCRIPT_DIR/de/kde/effects.sh"
            DE_SERVICES="$SCRIPT_DIR/de/kde/services.sh"
            DE_COMPOSITOR_GPU="$SCRIPT_DIR/de/kde/compositor-gpu.sh"
            log "Detected Desktop Environment: KDE Plasma"
            ;;
        unknown)
            warn "Could not detect desktop environment"
            warn "Display and visual effects management will be skipped"
            DE_DISPLAY=""
            DE_VISUAL=""
            DE_SERVICES=""
            DE_COMPOSITOR_GPU=""
            ;;
    esac
}

# --- Status command -----------------------------------------------------------
show_status() {
    echo "============================================================"
    echo "  Zephyrus G16 Power Status (Multi-DE)"
    echo "============================================================"
    echo ""

    # Detect DE
    local de
    de=$(detect_desktop_environment)
    echo "Desktop Environment: $de"
    echo ""

    # Power source
    local source
    source=$(detect_power_source)
    echo "Power source    : $source"

    # Battery info
    if [[ -f /sys/class/power_supply/BAT1/capacity ]]; then
        local cap
        cap=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
        local status
        status=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null)
        echo "Battery         : ${cap}% ($status)"
    fi

    # Current power draw
    if [[ -f /sys/class/power_supply/BAT1/power_now ]]; then
        local power_uw
        power_uw=$(cat /sys/class/power_supply/BAT1/power_now 2>/dev/null)
        if [[ -n "$power_uw" && "$power_uw" -gt 0 ]] 2>/dev/null; then
            local power_mw=$((power_uw / 1000))
            local power_w=$((power_mw / 1000))
            local power_frac=$(( (power_mw % 1000) / 10 ))
            printf "Power draw      : %d.%02dW\n" "$power_w" "$power_frac"
        fi
    elif [[ -f /sys/class/power_supply/BAT1/current_now ]]; then
        local curr
        curr=$(cat /sys/class/power_supply/BAT1/current_now 2>/dev/null)
        local volt
        volt=$(cat /sys/class/power_supply/BAT1/voltage_now 2>/dev/null)
        if [[ -n "$curr" && -n "$volt" ]]; then
            local power_mw=$(( (curr / 1000) * (volt / 1000) / 1000 ))
            local power_w=$((power_mw / 1000))
            local power_frac=$(( (power_mw % 1000) / 10 ))
            printf "Power draw      : ~%d.%02dW (estimated)\n" "$power_w" "$power_frac"
        fi
    fi

    echo ""

    # Call status from core modules
    if [[ -x "$SCRIPT_DIR/core/cpu-power.sh" ]]; then
        "$SCRIPT_DIR/core/cpu-power.sh" status
        echo ""
    fi
    
    if [[ -x "$SCRIPT_DIR/core/gpu.sh" ]]; then
        "$SCRIPT_DIR/core/gpu.sh" status
        echo ""
    fi
    
    # Call DE-specific status
    load_de_modules "$de"
    if [[ -n "$DE_DISPLAY" ]] && [[ -x "$DE_DISPLAY" ]]; then
        "$DE_DISPLAY" status
        echo ""
    fi
    
    if [[ -n "$DE_VISUAL" ]] && [[ -x "$DE_VISUAL" ]]; then
        "$DE_VISUAL" status
        echo ""
    fi

    echo "============================================================"
}

# --- Battery Mode -------------------------------------------------------------
apply_battery() {
    log "=== Applying BATTERY mode ==="
    log ""
    
    # Detect DE and load modules
    local de
    de=$(detect_desktop_environment)
    load_de_modules "$de"

    # Core modules (DE-agnostic)
    log "--- Core Power Settings ---"
    [[ -x "$SCRIPT_DIR/core/cpu-power.sh" ]] && "$SCRIPT_DIR/core/cpu-power.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/cpu-cores.sh" ]] && "$SCRIPT_DIR/core/cpu-cores.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/kernel-tunables.sh" ]] && "$SCRIPT_DIR/core/kernel-tunables.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/pci-power.sh" ]] && "$SCRIPT_DIR/core/pci-power.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/audio.sh" ]] && "$SCRIPT_DIR/core/audio.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/usb.sh" ]] && "$SCRIPT_DIR/core/usb.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/network.sh" ]] && "$SCRIPT_DIR/core/network.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/platform.sh" ]] && "$SCRIPT_DIR/core/platform.sh" battery
    log ""
    
    # DE-specific: display refresh rate first (user-visible, fast)
    if [[ -n "$DE_DISPLAY" ]] && [[ -x "$DE_DISPLAY" ]]; then
        log "--- Display Settings ($de) ---"
        "$DE_DISPLAY" battery
        log ""
    fi
    
    [[ -x "$SCRIPT_DIR/core/gpu.sh" ]] && timeout 60 "$SCRIPT_DIR/core/gpu.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/chromium-igpu.sh" ]] && "$SCRIPT_DIR/core/chromium-igpu.sh" battery
    log ""
    
    [[ -x "$SCRIPT_DIR/core/nvme-power.sh" ]] && "$SCRIPT_DIR/core/nvme-power.sh" battery
    log ""
    
    if [[ -n "$DE_VISUAL" ]] && [[ -x "$DE_VISUAL" ]]; then
        log "--- Visual Effects ($de) ---"
        "$DE_VISUAL" battery
        log ""
    fi
    
    if [[ -n "$DE_SERVICES" ]] && [[ -x "$DE_SERVICES" ]]; then
        log "--- Background Services ($de) ---"
        "$DE_SERVICES" battery
        log ""
    fi
    
    if [[ -n "$DE_COMPOSITOR_GPU" ]] && [[ -x "$DE_COMPOSITOR_GPU" ]]; then
        log "--- Compositor GPU Isolation ($de) ---"
        "$DE_COMPOSITOR_GPU" battery
        log ""
    fi

    log ""
    log "=== Battery mode applied ==="
    log "Desktop Environment: $de"
    log "Run '$0 status' to verify current state"
}

# --- AC / Beast Mode ----------------------------------------------------------
apply_ac() {
    log "=== Applying AC / BEAST mode ==="
    log ""
    
    # Detect DE and load modules
    local de
    de=$(detect_desktop_environment)
    load_de_modules "$de"

    # Core modules (DE-agnostic)
    log "--- Core Power Settings ---"
    [[ -x "$SCRIPT_DIR/core/cpu-cores.sh" ]] && "$SCRIPT_DIR/core/cpu-cores.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/cpu-power.sh" ]] && "$SCRIPT_DIR/core/cpu-power.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/platform.sh" ]] && "$SCRIPT_DIR/core/platform.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/kernel-tunables.sh" ]] && "$SCRIPT_DIR/core/kernel-tunables.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/pci-power.sh" ]] && "$SCRIPT_DIR/core/pci-power.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/audio.sh" ]] && "$SCRIPT_DIR/core/audio.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/usb.sh" ]] && "$SCRIPT_DIR/core/usb.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/network.sh" ]] && "$SCRIPT_DIR/core/network.sh" ac
    log ""
    
    # DE-specific: display refresh rate first (user-visible, fast)
    if [[ -n "$DE_DISPLAY" ]] && [[ -x "$DE_DISPLAY" ]]; then
        log "--- Display Settings ($de) ---"
        "$DE_DISPLAY" ac
        log ""
    fi
    
    [[ -x "$SCRIPT_DIR/core/gpu.sh" ]] && timeout 60 "$SCRIPT_DIR/core/gpu.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/chromium-igpu.sh" ]] && "$SCRIPT_DIR/core/chromium-igpu.sh" ac
    log ""
    
    [[ -x "$SCRIPT_DIR/core/nvme-power.sh" ]] && "$SCRIPT_DIR/core/nvme-power.sh" ac
    log ""
    
    if [[ -n "$DE_VISUAL" ]] && [[ -x "$DE_VISUAL" ]]; then
        log "--- Visual Effects ($de) ---"
        "$DE_VISUAL" ac
        log ""
    fi
    
    if [[ -n "$DE_SERVICES" ]] && [[ -x "$DE_SERVICES" ]]; then
        log "--- Background Services ($de) ---"
        "$DE_SERVICES" ac
        log ""
    fi
    
    if [[ -n "$DE_COMPOSITOR_GPU" ]] && [[ -x "$DE_COMPOSITOR_GPU" ]]; then
        log "--- Compositor GPU Isolation ($de) ---"
        "$DE_COMPOSITOR_GPU" ac
        log ""
    fi

    log ""
    log "=== AC / Beast mode applied ==="
    log "Desktop Environment: $de"
    log "Run '$0 status' to verify current state"
}

# --- Main ---------------------------------------------------------------------
main() {
    local mode="${1:-}"
    local flag="${2:-}"

    if [[ "$flag" == "--dry-run" ]]; then
        export DRY_RUN=true
        log "(DRY RUN — no changes will be applied)"
        log ""
    fi

    case "$mode" in
        battery)
            if [[ "$EUID" -ne 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
                echo "Error: 'battery' mode requires root. Use: sudo $0 battery" >&2
                exit 1
            fi
            apply_battery
            ;;
        ac)
            if [[ "$EUID" -ne 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
                echo "Error: 'ac' mode requires root. Use: sudo $0 ac" >&2
                exit 1
            fi
            apply_ac
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "Commands:"
            echo "  battery          Apply battery-saving optimizations (requires root)"
            echo "  ac               Apply full-performance AC mode (requires root)"
            echo "  status           Show current power state (no root needed)"
            echo ""
            echo "Flags:"
            echo "  --dry-run        Preview changes without applying them"
            echo ""
            echo "Supported Desktop Environments:"
            echo "  - GNOME (Wayland/X11)"
            echo "  - KDE Plasma (Wayland/X11)"
            echo ""
            echo "Current DE: $(detect_desktop_environment)"
            exit 1
            ;;
    esac
}

main "$@"
