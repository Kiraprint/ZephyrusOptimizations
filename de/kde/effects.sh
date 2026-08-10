#!/usr/bin/env bash
# =============================================================================
# effects.sh — KDE Plasma effects management for power savings
#
# Test independently:
#   ./effects.sh status
#   ./effects.sh battery
#   ./effects.sh ac
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../core/common.sh"
LOG_PREFIX="[kde-effects]"

# KDE config files (detected per-user later)
# KWIN_CONFIG will be ~/.config/kwinrc for the display user

# Effects to disable on battery (power saving)
BATTERY_DISABLE_EFFECTS=(
    "blurEnabled"                           # Blur effect (GPU intensive)
    "contrastEnabled"                       # Contrast effect
    "kwin4_effect_translucencyEnabled"      # Translucency
    "kwin4_effect_fadingpopupsEnabled"      # Fading popups
    "slideEnabled"                          # Slide animation
    "kwin4_effect_morphingpopupsEnabled"    # Morphing popups
    "kwin4_effect_squashEnabled"            # Squash animation
    "zoomEnabled"                           # Zoom effect
    "windowapertureEnabled"                 # Window aperture
)

set_kwin_config() {
    local key="$1"
    local value="$2"
    local description="${3:-$key}"
    
    # Detect logged-in user
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        log "  [skip] Cannot detect display user"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would set $description to $value"
        return 0
    fi
    
    # Check if kwriteconfig5 or kwriteconfig6 is available
    local kwrite_cmd=""
    if command -v kwriteconfig6 &>/dev/null; then
        kwrite_cmd="kwriteconfig6"
    elif command -v kwriteconfig5 &>/dev/null; then
        kwrite_cmd="kwriteconfig5"
    else
        log "  [skip] kwriteconfig not found (KDE Plasma not installed?)"
        return 0
    fi
    
    # Set the config value
    if run_as_display_user "$display_user" $kwrite_cmd --file kwinrc --group Plugins --key "$key" "$value" 2>/dev/null; then
        log "  [ok] $description → $value"
        
        # Reconfigure KWin to apply changes
        local qdbus_cmd=""
        if command -v qdbus6 &>/dev/null; then
            qdbus_cmd="qdbus6"
        elif command -v qdbus &>/dev/null; then
            qdbus_cmd="qdbus"
        fi
        
        if [[ -n "$qdbus_cmd" ]]; then
            run_as_display_user "$display_user" $qdbus_cmd org.kde.KWin /KWin reconfigure 2>/dev/null || true
        fi
    else
        warn "Failed to set $description"
    fi
}

show_status() {
    echo "=== KDE Effects Status ==="
    
    # Detect logged-in user
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        echo "Cannot detect display user (no active KDE session)"
        return 1
    fi
    
    echo "Power-managed effects:"
    
    # Check if kreadconfig is available
    local kread_cmd=""
    if command -v kreadconfig6 &>/dev/null; then
        kread_cmd="kreadconfig6"
    elif command -v kreadconfig5 &>/dev/null; then
        kread_cmd="kreadconfig5"
    else
        echo "  kreadconfig not found (KDE Plasma not installed?)"
        return 1
    fi
    
    for effect in "${BATTERY_DISABLE_EFFECTS[@]}"; do
        local value
        value=$(run_as_display_user "$display_user" $kread_cmd --file kwinrc --group Plugins --key "$effect" 2>/dev/null)
        if [[ -z "$value" ]]; then
            value="not set (defaults to enabled)"
        fi
        echo "  $effect: $value"
    done
    
    echo ""
    echo "Compositor status:"
    local qdbus_cmd=""
    if command -v qdbus6 &>/dev/null; then
        qdbus_cmd="qdbus6"
    elif command -v qdbus &>/dev/null; then
        qdbus_cmd="qdbus"
    fi
    
    if [[ -n "$qdbus_cmd" ]]; then
        local compositor_active
        compositor_active=$(run_as_display_user "$display_user" $qdbus_cmd org.kde.KWin /Compositor active 2>/dev/null || echo "unknown")
        echo "  Active: $compositor_active"
    else
        echo "  (qdbus not found - cannot query compositor)"
    fi
}

apply_battery() {
    log "=== Applying battery KDE effects settings ==="
    
    log "Step 1: Disable GPU-intensive visual effects (saves ~1-1.5W)"
    # Disable heavy effects
    for effect in "${BATTERY_DISABLE_EFFECTS[@]}"; do
        set_kwin_config "$effect" "false" "$effect"
    done
    
    log ""
    log "Step 2: Reduce compositor refresh rate to 60Hz (saves ~0.5-1W)"
    # Reduce refresh rate to 60Hz if higher (saves GPU power)
    set_kwin_config "MaxFPS" "60" "Maximum FPS (60Hz on battery)"
    set_kwin_config "RefreshRate" "60000" "Refresh rate (60Hz)"
    
    # Instant animations (less frames = less GPU work)
    set_kwin_config "AnimationSpeed" "4" "Animation speed (instant)"
    
    log ""
    log "Battery KDE effects settings applied"
    log "Estimated power savings: 1.5-2.5W from compositor optimizations"
}

apply_ac() {
    log "=== Applying AC KDE effects settings ==="
    
    log "Restoring full visual effects and compositor performance"
    # Enable full effects
    for effect in "${BATTERY_DISABLE_EFFECTS[@]}"; do
        set_kwin_config "$effect" "true" "$effect"
    done
    
    # Restore high refresh rate (if monitor supports it)
    set_kwin_config "MaxFPS" "240" "Maximum FPS (240Hz on AC)"
    set_kwin_config "RefreshRate" "240000" "Refresh rate (240Hz)"
    
    # Full animation speed
    set_kwin_config "AnimationSpeed" "3" "Animation speed (normal)"
    
    log ""
    log "AC KDE effects settings applied (full visual effects + performance)"
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
            echo "  battery    Disable heavy effects for battery savings"
            echo "  ac         Enable full visual effects"
            echo "  status     Show current effect states"
            exit 1
            ;;
    esac
}

main "$@"
