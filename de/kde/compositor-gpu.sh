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
    local gpu_env_file="$kde_env_dir/gpu-kwin.sh"
    
    # Check if env file exists
    if [[ -f "$gpu_env_file" ]]; then
        echo "GPU isolation: ACTIVE (permanent — KWin uses iGPU on AC and battery)"
        echo "  User: $display_user"
        echo "  File: $gpu_env_file"
        echo "  Contents:"
        cat "$gpu_env_file" | sed 's/^/    /'
    else
        echo "GPU isolation: INACTIVE (isolation file missing — run battery or ac once)"
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

# Write the permanent KWin iGPU isolation env file — applies on AC AND battery.
# KWin must never open the dGPU render node / EGL ICD; the dGPU is reserved
# for explicit ML/CUDA/Vulkan workloads (launched via prime-run etc).
write_isolation_file() {
    local display_user="$1"
    local user_home
    user_home=$(get_user_home "$display_user")
    local kde_env_dir="$user_home/.config/plasma-workspace/env"
    local gpu_env_file="$kde_env_dir/gpu-kwin.sh"

    if [[ ! -d "$kde_env_dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  [dry-run] Would create directory: $kde_env_dir"
            return 0
        fi
        if [[ "$EUID" -eq 0 ]]; then
            sudo -u "$display_user" mkdir -p "$kde_env_dir"
        else
            mkdir -p "$kde_env_dir"
        fi
        log "  [ok] Created directory: $kde_env_dir"
    fi

    local env_content='#!/usr/bin/env bash
# Force KWin + KDE session to use only the Intel iGPU (always: AC and battery).
# The NVIDIA dGPU stays reserved for explicit ML/CUDA/Vulkan workloads.
# Ref: KDE bug 521814/521914, cardwire sleep diagnostics

export __GLX_VENDOR_LIBRARY_NAME=mesa
export DRI_PRIME=0

# KWin 6.7 GpuManager: restrict direct render-node opens to the iGPU only.
# Resolved dynamically — DRM minor numbers (renderD12x) swap across boots,
# by-path is PCI-address-stable.
export KWIN_RENDER_NODES=$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-render)
# Stop the Vulkan device scan that wakes the dGPU (Vulkan can bypass KWIN_RENDER_NODES)
export KWIN_DISABLE_VULKAN=1
# Load only the Mesa EGL ICD -> libEGL_nvidia never dlopened -> /dev/nvidiactl never opened
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json

# Verify variables are set
echo "[compositor-gpu] Forcing iGPU (mesa EGL, render node via by-path)" >&2
'

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would create: $gpu_env_file"
        log "  [dry-run] Contents:"
        echo "$env_content" | sed 's/^/    /'
        return 0
    fi

    if [[ "$EUID" -eq 0 ]]; then
        echo "$env_content" > "$gpu_env_file"
        chown "$display_user:$display_user" "$gpu_env_file"
    else
        echo "$env_content" > "$gpu_env_file"
    fi
    chmod +x "$gpu_env_file"
    # Remove the old battery-only toggle (pre-permanent-isolation)
    rm -f "$kde_env_dir/gpu-battery.sh"
    log "  [ok] iGPU isolation active: $gpu_env_file"
}

apply_battery() {
    log "=== Applying compositor GPU settings (battery) ==="

    local display_user
    display_user=$(detect_display_user)

    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi

    write_isolation_file "$display_user"

    log ""
    log "Battery compositor GPU settings applied (isolation is permanent)"
    log "⚠️  IMPORTANT: You must logout and login for changes to take effect"
}

apply_ac() {
    log "=== Applying AC compositor GPU settings (iGPU stays) ==="

    local display_user
    display_user=$(detect_display_user)

    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi

    # Isolation is permanent by design: KWin never touches the dGPU on AC
    # either. The dGPU remains available for explicit ML/gaming workloads
    # (prime-run / Vulkan) — it just is not used for desktop compositing.
    write_isolation_file "$display_user"

    log ""
    log "AC compositor GPU settings applied (isolation stays active)"
    log "⚠️  IMPORTANT: You must logout and login for changes to take effect"
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
