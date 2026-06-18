#!/usr/bin/env bash
# =============================================================================
# browser-brave.sh — Brave Browser GPU and rendering optimizations
#
# Enables Intel integrated GPU optimizations for Brave:
#   - Vulkan rendering (faster than ANGLE/OpenGL)
#   - Hardware video encoding
#   - Skia Graphite rendering backend
#   - Optimized memory management
#
# Test independently:
#   ./browser-brave.sh apply --dry-run
#   ./browser-brave.sh battery
#   ./browser-brave.sh ac
#   ./browser-brave.sh status
#
# Note: Restart Brave after applying to activate flags
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[browser-brave]"

# Brave user data directory
BRAVE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/BraveSoftware/Brave-Browser/Default"
BRAVE_FLAGS_FILE="$BRAVE_CONFIG_DIR/Preferences"

# Brave profile name (usually "Default" but could vary)
# This function will update the Preferences JSON
update_brave_preferences() {
    local key="$1"
    local value="$2"
    
    # If Preferences file doesn't exist, create a minimal one
    if [[ ! -f "$BRAVE_FLAGS_FILE" ]]; then
        log "Brave Preferences file not found. Will be created on next Brave startup."
        return 0
    fi
    
    # Use jq to safely update JSON if available, otherwise warn
    if ! command -v jq &>/dev/null; then
        warn "jq not found. Cannot safely update Brave preferences."
        warn "Install with: sudo pacman -S jq"
        return 1
    fi
    
    # Create backup
    cp "$BRAVE_FLAGS_FILE" "$BRAVE_FLAGS_FILE.backup.$(date +%s)"
    
    # Update JSON using jq
    jq --arg key "$key" --argjson value "$value" \
        '.[$key] = $value' \
        "$BRAVE_FLAGS_FILE" > "$BRAVE_FLAGS_FILE.tmp" && \
    mv "$BRAVE_FLAGS_FILE.tmp" "$BRAVE_FLAGS_FILE"
}

# Create Brave command line flags file
setup_brave_flags() {
    local profile_dir="$BRAVE_CONFIG_DIR"
    
    # Ensure Brave config directory exists
    mkdir -p "$profile_dir"
    
    # The flags are set via command line arguments passed to brave at startup
    # We can't directly set these in the config, but we can verify they're passed
    log "Brave optimization flags should be passed at launch:"
    log "  --enable-features=Vulkan,VulkanFromANGLE"
    log "  --enable-features=HardwareMediaKeyHandling"
    log "  --enable-features=SkiaGraphite"
}

show_status() {
    echo "=== Brave Browser Status ==="
    
    if ! command -v brave &>/dev/null; then
        echo "Brave not installed"
        return 1
    fi
    
    local version
    version=$(brave --version 2>/dev/null || echo "unknown")
    echo "Brave version    : $version"
    
    if [[ -d "$BRAVE_CONFIG_DIR" ]]; then
        echo "Config directory : $BRAVE_CONFIG_DIR"
        echo "  Preferences file exists: $(test -f "$BRAVE_FLAGS_FILE" && echo "yes" || echo "no")"
    else
        echo "Config directory : (not yet created — will be on first Brave launch)"
    fi
    
    echo ""
    echo "GPU/Rendering Flags to enable:"
    echo "  --enable-features=Vulkan              (Vulkan rendering: faster on Intel iGPU)"
    echo "  --enable-features=VulkanFromANGLE     (Fallback Vulkan through ANGLE)"
    echo "  --enable-features=SkiaGraphite        (New rendering backend)"
    echo "  --disable-blink-features=AutomationControlled (Disable headless mode hints)"
    echo ""
    echo "Video Encoding Flags:"
    echo "  --enable-features=HardwareMediaKeyHandling"
    echo ""
    echo "To apply: edit ~/.bashrc or create a Brave launcher alias"
}

apply_intel_optimizations() {
    log "=== Applying Intel GPU optimizations for Brave ==="
    
    if ! command -v brave &>/dev/null; then
        warn "Brave not found. Install with: sudo pacman -S brave-bin"
        return 1
    fi
    
    log ""
    log "Creating Brave launcher wrapper..."
    
    # Create a launcher script that sets the flags
    local launcher_script="$HOME/.local/bin/brave-optimized"
    mkdir -p "$(dirname "$launcher_script")"
    
    cat > "$launcher_script" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Brave launcher with Intel GPU optimizations
/usr/bin/brave \
  --enable-features=Vulkan,VulkanFromANGLE \
  --enable-features=SkiaGraphite \
  --enable-features=HardwareMediaKeyHandling \
  --enable-gpu-rasterization \
  --enable-native-gpu-memory-buffers \
  --ozone-platform=wayland \
  "$@"
LAUNCHER_EOF
    
    chmod +x "$launcher_script"
    sysfs_success_msg "Created: $launcher_script"
    
    log ""
    log "To make this the default:"
    log "  1. Update your shell alias in ~/.bashrc or ~/.zshrc:"
    log "     alias brave='~/.local/bin/brave-optimized'"
    log ""
    log "  2. Or update the .desktop file:"
    log "     sed -i 's|Exec=.*|Exec=$launcher_script|' ~/.local/share/applications/brave.desktop"
    log ""
    log "  3. Restart Brave to activate optimizations"
}

apply_battery() {
    log "=== Applying Brave battery optimization ==="
    
    if ! command -v brave &>/dev/null; then
        warn "Brave not found"
        return 1
    fi
    
    # Battery mode: disable heavy features
    local launcher_script="$HOME/.local/bin/brave-battery"
    mkdir -p "$(dirname "$launcher_script")"
    
    cat > "$launcher_script" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Brave launcher with battery optimizations
/usr/bin/brave \
  --enable-features=Vulkan \
  --disable-extensions \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-breakpad \
  --disable-client-side-phishing-detection \
  --disable-component-extensions-with-background-pages \
  --disable-component-update \
  --disable-crx-installer \
  --disable-device-discovery-notifications \
  --disable-extension-update \
  --disable-sync \
  --ozone-platform=wayland \
  "$@"
LAUNCHER_EOF
    
    chmod +x "$launcher_script"
    log "Battery launcher: $launcher_script"
}

apply_ac() {
    log "=== Applying Brave AC power optimization ==="
    
    apply_intel_optimizations
}

main() {
    local mode
    mode=$(parse_module_args "$@")
    
    case "$mode" in
        apply)       apply_intel_optimizations ;;
        battery)     apply_battery ;;
        ac)          apply_ac ;;
        status)      show_status ;;
        *)
            echo "Usage: $0 {apply|battery|ac|status} [--dry-run]"
            echo ""
            echo "  apply      Create optimized Brave launcher with Intel GPU flags"
            echo "  battery    Create battery-optimized Brave launcher (minimal features)"
            echo "  ac         Create full-featured Brave launcher (GPU acceleration)"
            echo "  status     Show Brave GPU/rendering configuration"
            exit 1
            ;;
    esac
}

main "$@"
