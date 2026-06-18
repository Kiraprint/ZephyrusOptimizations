#!/usr/bin/env bash
# =============================================================================
# chromium-igpu.sh — Force Chromium/Electron apps to use iGPU
#
# This script creates/removes flag files that force Chromium-based apps
# (Brave, Chrome, Electron, VSCode, Cursor, etc.) to use Intel iGPU only.
#
# Chromium apps read flags from:
#   - ~/.config/brave-flags.conf
#   - ~/.config/electron-flags.conf
#   - ~/.config/electron39-flags.conf (version-specific)
#   - ~/.config/code-flags.conf (VSCode)
#   - ~/.config/cursor-flags.conf (Cursor)
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[chromium-igpu]"

# Get actual display user's home directory
get_user_home() {
    local user="$1"
    eval echo "~$user"
}

# Chromium GPU flags for forcing iGPU
CHROMIUM_GPU_FLAGS=(
    "--use-gl=angle"
    "--use-angle=gl"
    "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder"
    "--disable-features=UseChromeOSDirectVideoDecoder"
    "--ozone-platform=wayland"
)

# Flag files for different Chromium-based apps
FLAG_FILES=(
    "brave-flags.conf"
    "chromium-flags.conf"
    "chrome-flags.conf"
    "electron-flags.conf"
    "electron39-flags.conf"
    "code-flags.conf"
    "cursor-flags.conf"
)

show_status() {
    echo "=== Chromium/Electron iGPU Status ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        echo "Cannot detect display user"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$display_user")
    
    echo "User: $display_user"
    echo "Config directory: $user_home/.config"
    echo ""
    
    local flags_active=0
    
    for flag_file in "${FLAG_FILES[@]}"; do
        local full_path="$user_home/.config/$flag_file"
        if [[ -f "$full_path" ]]; then
            echo "✓ $flag_file (iGPU forced)"
            flags_active=1
        else
            echo "  $flag_file (not set)"
        fi
    done
    
    echo ""
    
    if [[ "$flags_active" -eq 1 ]]; then
        echo "Status: iGPU forced for some apps"
        echo "Note: Apps need restart to pick up flag changes"
    else
        echo "Status: No GPU restrictions (apps use dGPU by default)"
    fi
}

create_flag_file() {
    local file_path="$1"
    local display_user="$2"
    
    local content=""
    for flag in "${CHROMIUM_GPU_FLAGS[@]}"; do
        content="${content}${flag}\n"
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would create: $file_path"
        return 0
    fi
    
    # Create the file
    if [[ "$EUID" -eq 0 ]]; then
        # Running as root, write then chown
        echo -e "$content" > "$file_path"
        chown "$display_user:$display_user" "$file_path"
    else
        echo -e "$content" > "$file_path"
    fi
    
    log "  [ok] Created: $(basename "$file_path")"
}

remove_flag_file() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  [dry-run] Would remove: $file_path"
        return 0
    fi
    
    rm -f "$file_path"
    log "  [ok] Removed: $(basename "$file_path")"
}

apply_battery() {
    log "=== Forcing Chromium/Electron apps to use iGPU ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$display_user")
    local config_dir="$user_home/.config"
    
    log "Target user: $display_user"
    log "Config directory: $config_dir"
    log ""
    
    # Create config dir if needed
    if [[ ! -d "$config_dir" ]] && [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$config_dir"
        if [[ "$EUID" -eq 0 ]]; then
            chown "$display_user:$display_user" "$config_dir"
        fi
    fi
    
    # Create all flag files
    local created_count=0
    for flag_file in "${FLAG_FILES[@]}"; do
        local full_path="$config_dir/$flag_file"
        
        # Skip if already exists with correct content
        if [[ -f "$full_path" ]]; then
            if grep -q "use-gl=angle" "$full_path" 2>/dev/null; then
                log "  [skip] $flag_file already configured"
                continue
            fi
        fi
        
        create_flag_file "$full_path" "$display_user"
        created_count=$((created_count + 1))
    done
    
    log ""
    
    if [[ "$created_count" -gt 0 ]]; then
        log "✓ Created/updated $created_count flag files"
        log ""
        log "⚠️  IMPORTANT: Restart these apps to apply changes:"
        log "   - Brave Browser"
        log "   - Cursor / VSCode"
        log "   - Any Electron apps (Discord, Slack, etc.)"
        log ""
        log "Quick restart: Close the apps and reopen them"
    else
        log "All apps already configured for iGPU"
    fi
}

apply_ac() {
    log "=== Removing Chromium/Electron iGPU restrictions ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$display_user")
    local config_dir="$user_home/.config"
    
    log "Target user: $display_user"
    log ""
    
    # Remove all flag files
    local removed_count=0
    for flag_file in "${FLAG_FILES[@]}"; do
        local full_path="$config_dir/$flag_file"
        
        if [[ -f "$full_path" ]]; then
            remove_flag_file "$full_path"
            removed_count=$((removed_count + 1))
        fi
    done
    
    log ""
    
    if [[ "$removed_count" -gt 0 ]]; then
        log "✓ Removed $removed_count flag files"
        log ""
        log "⚠️  IMPORTANT: Restart apps to use automatic GPU selection"
        log "   (They may use dGPU for better performance)"
    else
        log "No flag files to remove"
    fi
}

list_chromium_processes() {
    log "=== Running Chromium/Electron processes ==="
    log ""
    
    # Find Chromium-based processes
    local procs
    procs=$(ps aux | grep -E "(brave|chrome|electron|cursor|code)" | grep -v grep | grep -v "chromium-igpu.sh")
    
    if [[ -z "$procs" ]]; then
        log "No Chromium/Electron processes found"
        return 0
    fi
    
    echo "$procs" | awk '{print $11}' | sed 's|.*/||' | sort -u | while read -r proc; do
        local pids
        pids=$(pgrep -x "$proc" 2>/dev/null | head -3 | tr '\n' ' ')
        if [[ -n "$pids" ]]; then
            echo "  $proc (PIDs: $pids)"
        fi
    done
}

main() {
    local mode=""
    
    for arg in "$@"; do
        case "$arg" in
            battery|ac|status|list)
                mode="$arg"
                ;;
            --dry-run)
                DRY_RUN="true"
                export DRY_RUN
                ;;
        esac
    done
    
    if [[ -z "$mode" ]]; then
        echo "Usage: $0 {battery|ac|status|list} [--dry-run]"
        echo ""
        echo "  battery    Force Chromium/Electron apps to use iGPU"
        echo "  ac         Remove iGPU restrictions (automatic GPU selection)"
        echo "  status     Show current flag file status"
        echo "  list       List running Chromium/Electron processes"
        echo ""
        echo "Affected apps: Brave, Chrome, VSCode, Cursor, Discord, Slack, etc."
        echo "Note: Apps must be restarted after flag changes"
        echo ""
        echo "This creates flag files in ~/.config/ to force iGPU usage"
        exit 1
    fi
    
    case "$mode" in
        battery)
            apply_battery
            ;;
        ac)
            apply_ac
            ;;
        status)
            show_status
            ;;
        list)
            list_chromium_processes
            ;;
    esac
}

main "$@"
