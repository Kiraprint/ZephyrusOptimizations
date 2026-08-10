#!/usr/bin/env bash
# =============================================================================
# compositor-gpu-dynamic.sh — Dynamically switch KDE compositor GPU (EXPERIMENTAL)
#
# This version attempts to switch GPU without logout by:
# 1. Setting systemd user environment
# 2. Restarting KWin compositor
#
# WARNING: This is experimental and may cause temporary screen glitches
# The static approach (requiring logout) is more reliable.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../core/common.sh"
LOG_PREFIX="[compositor-gpu-dyn]"

apply_battery_dynamic() {
    log "=== Applying battery compositor GPU (dynamic) ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    log "Setting systemd user environment for $display_user..."
    
    # Set environment for the user session
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set __GLX_VENDOR_LIBRARY_NAME=mesa"
        log "  [dry-run] Would set DRI_PRIME=0"
        log "  [dry-run] Would restart kwin_wayland"
    else
        run_as_display_user "$display_user" systemctl --user set-environment __GLX_VENDOR_LIBRARY_NAME=mesa
        run_as_display_user "$display_user" systemctl --user set-environment DRI_PRIME=0
        log "  [ok] Set GPU environment variables"
        
        # Restart KWin to pick up new environment
        log "  [info] Restarting KWin compositor..."
        run_as_display_user "$display_user" systemctl --user restart plasma-kwin_wayland.service
        log "  [ok] KWin restarted with iGPU"
    fi
    
    log ""
    log "⚠️  Note: Screen may flicker during compositor restart"
    log "⚠️  Applications already running will keep their GPU until restarted"
}

apply_ac_dynamic() {
    log "=== Applying AC compositor GPU (dynamic) ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    log "Unsetting systemd user environment for $display_user..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would unset __GLX_VENDOR_LIBRARY_NAME"
        log "  [dry-run] Would unset DRI_PRIME"
        log "  [dry-run] Would restart kwin_wayland"
    else
        run_as_display_user "$display_user" systemctl --user unset-environment __GLX_VENDOR_LIBRARY_NAME
        run_as_display_user "$display_user" systemctl --user unset-environment DRI_PRIME
        log "  [ok] Unset GPU environment variables"
        
        # Restart KWin to pick up new environment
        log "  [info] Restarting KWin compositor..."
        run_as_display_user "$display_user" systemctl --user restart plasma-kwin_wayland.service
        log "  [ok] KWin restarted with automatic GPU selection"
    fi
    
    log ""
    log "⚠️  Note: Screen may flicker during compositor restart"
}

show_status() {
    echo "=== KDE Compositor GPU Status (Dynamic) ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        echo "Cannot detect display user"
        return 1
    fi
    
    echo "Systemd user environment:"
    local glx_vendor dri_prime
    glx_vendor=$(run_as_display_user "$display_user" systemctl --user show-environment | grep "^__GLX_VENDOR_LIBRARY_NAME=" | cut -d= -f2)
    dri_prime=$(run_as_display_user "$display_user" systemctl --user show-environment | grep "^DRI_PRIME=" | cut -d= -f2)
    
    if [[ -n "$glx_vendor" ]] || [[ -n "$dri_prime" ]]; then
        echo "  GPU isolation: ACTIVE"
        echo "  __GLX_VENDOR_LIBRARY_NAME: ${glx_vendor:-not set}"
        echo "  DRI_PRIME: ${dri_prime:-not set}"
    else
        echo "  GPU isolation: INACTIVE (automatic selection)"
    fi
    
    echo ""
    echo "Current session:"
    echo "  __GLX_VENDOR_LIBRARY_NAME: ${__GLX_VENDOR_LIBRARY_NAME:-not set}"
    echo "  DRI_PRIME: ${DRI_PRIME:-not set}"
}

main() {
    local mode
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && DRY_RUN="true" && export DRY_RUN && break
    done
    mode=$(parse_module_args "$@")
    
    case "$mode" in
        battery)  apply_battery_dynamic ;;
        ac)       apply_ac_dynamic ;;
        status)   show_status ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "  battery    Force compositor to use iGPU (dynamic, no logout needed)"
            echo "  ac         Allow automatic GPU selection (dynamic, no logout needed)"
            echo "  status     Show current compositor GPU configuration"
            echo ""
            echo "EXPERIMENTAL: This restarts KWin compositor (screen may flicker)"
            echo "For a more reliable approach, use compositor-gpu.sh (requires logout)"
            exit 1
            ;;
    esac
}

main "$@"
