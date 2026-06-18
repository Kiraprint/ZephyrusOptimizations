#!/usr/bin/env bash
# =============================================================================
# compositor-gpu.sh — Force KDE compositor to use iGPU on battery
#
# Test independently:
#   ./compositor-gpu.sh status
#   ./compositor-gpu.sh battery
#   ./compositor-gpu.sh ac
#
# Strategy:
#   - On battery: Create env script to force Mesa (iGPU) rendering
#   - On AC: Remove env script to allow automatic GPU selection
#   - Requires logout/login to take effect
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../core/common.sh"
LOG_PREFIX="[compositor-gpu]"

# Get actual display user's home directory
get_user_home() {
    local user="$1"
    eval echo "~$user"
}

# KDE startup environment directory will be determined per-user

show_status() {
    echo "=== KDE Compositor GPU Status ==="
    
    # Detect display user
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        echo "Cannot detect display user"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$display_user")
    local kde_env_dir="$user_home/.config/plasma-workspace/env"
    local gpu_env_file="$kde_env_dir/gpu-battery.sh"
    
    # Check if env file exists
    if [[ -f "$gpu_env_file" ]]; then
        echo "GPU isolation: ACTIVE (iGPU forced)"
        echo "  User: $display_user"
        echo "  File: $gpu_env_file"
        echo "  Contents:"
        cat "$gpu_env_file" | sed 's/^/    /'
    else
        echo "GPU isolation: INACTIVE (automatic selection)"
        echo "  User: $display_user"
    fi
    
    echo ""
    echo "Current session GPU settings:"
    
    # Check current shell environment
    if [[ -n "${__GLX_VENDOR_LIBRARY_NAME:-}" ]]; then
        echo "  __GLX_VENDOR_LIBRARY_NAME: $__GLX_VENDOR_LIBRARY_NAME"
    else
        echo "  __GLX_VENDOR_LIBRARY_NAME: (not set - auto-select)"
    fi
    
    if [[ -n "${DRI_PRIME:-}" ]]; then
        echo "  DRI_PRIME: $DRI_PRIME"
        if [[ "$DRI_PRIME" == "0" ]]; then
            echo "    → Using iGPU (Intel Arc) ✓"
        elif [[ "$DRI_PRIME" == "1" ]]; then
            echo "    → Using dGPU (NVIDIA RTX 5090) ⚠️"
        fi
    else
        echo "  DRI_PRIME: (not set - auto-select)"
    fi
    
    echo ""
    echo "Note: Changes to GPU isolation require logout/login to take effect"
}

apply_battery() {
    log "=== Applying battery compositor GPU settings ==="
    
    # Detect display user
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$display_user")
    local kde_env_dir="$user_home/.config/plasma-workspace/env"
    local gpu_env_file="$kde_env_dir/gpu-battery.sh"
    
    # Create KDE env directory if needed
    if [[ ! -d "$kde_env_dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] Would create directory: $kde_env_dir"
        else
            # Create as the actual user
            if [[ "$EUID" -eq 0 ]]; then
                sudo -u "$display_user" mkdir -p "$kde_env_dir"
            else
                mkdir -p "$kde_env_dir"
            fi
            log "  [ok] Created directory: $kde_env_dir"
        fi
    fi
    
    # Create env file to force iGPU
    local env_content='#!/usr/bin/env bash
# Force KDE compositor to use Intel iGPU (battery mode)
# This prevents the NVIDIA dGPU from waking up during compositing

export __GLX_VENDOR_LIBRARY_NAME=mesa
export DRI_PRIME=0

# Verify variables are set
echo "[compositor-gpu] Battery mode: Forcing iGPU (DRI_PRIME=0)" >&2
'
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would create: $gpu_env_file"
        log "  [dry-run] Contents:"
        echo "$env_content" | sed 's/^/    /'
    else
        if [[ "$EUID" -eq 0 ]]; then
            # Write as root then chown
            echo "$env_content" > "$gpu_env_file"
            chown "$display_user:$display_user" "$gpu_env_file"
            chmod +x "$gpu_env_file"
        else
            echo "$env_content" > "$gpu_env_file"
            chmod +x "$gpu_env_file"
        fi
        log "  [ok] Created GPU isolation script: $gpu_env_file"
        log "  [ok] Owner: $display_user, Mode: executable"
    fi
    
    log ""
    log "Battery compositor GPU settings applied"
    log "⚠️  IMPORTANT: You must logout and login for changes to take effect"
    log ""
    log "To verify after logout:"
    log "  echo \$__GLX_VENDOR_LIBRARY_NAME  # Should show: mesa"
    log "  echo \$DRI_PRIME                  # Should show: 0"
}

apply_ac() {
    log "=== Applying AC compositor GPU settings ==="
    
    # Detect display user
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$display_user")
    local gpu_env_file="$user_home/.config/plasma-workspace/env/gpu-battery.sh"
    
    # Remove env file to allow automatic GPU selection
    if [[ -f "$gpu_env_file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] Would remove: $gpu_env_file"
        else
            rm -f "$gpu_env_file"
            log "  [ok] Removed GPU isolation script: $gpu_env_file"
        fi
    else
        log "  [skip] GPU isolation already inactive"
    fi
    
    log ""
    log "AC compositor GPU settings applied"
    log "⚠️  IMPORTANT: You must logout and login for changes to take effect"
    log ""
    log "After logout, compositor will use automatic GPU selection"
    log "(typically dGPU for better performance, or iGPU if dGPU is suspended)"
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
            echo "  battery    Force compositor to use iGPU (prevents dGPU wake)"
            echo "  ac         Allow automatic GPU selection"
            echo "  status     Show current compositor GPU configuration"
            echo ""
            echo "NOTE: Changes require logout/login to take effect"
            echo ""
            echo "This module creates/removes: ~/.config/plasma-workspace/env/gpu-battery.sh"
            exit 1
            ;;
    esac
}

main "$@"
