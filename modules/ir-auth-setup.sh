#!/bin/bash
#
# IR Authentication Configuration for ASUS Zephyrus G16 (GU605CX)
# Configures howdy for face recognition login and sudo
#
# Hardware:
#   Camera: Shinetech USB2.0 FHD UVC WebCam (3277:0060)
#   IR Camera: /dev/video2 (640x400 Greyscale @ 15fps)
#   iGPU: Intel Arc Graphics (Xe LPG) - supports CNN acceleration
#   CPU: Intel Core Ultra 9 285H (Arrow Lake)
#
# Prerequisites:
#   Install howdy first: yay -S howdy
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        exit 1
    fi
}

check_howdy_installed() {
    if ! command -v howdy &>/dev/null; then
        log_error "howdy is not installed"
        log_info "Install it first: yay -S howdy"
        exit 1
    fi
    log_ok "howdy is installed ($(howdy --version 2>/dev/null || echo 'version unknown'))"
}

detect_ir_camera() {
    log_info "Detecting IR camera..."
    
    # Check for video devices
    if [[ ! -e /dev/video2 ]]; then
        log_error "IR camera not found at /dev/video2"
        log_info "Available video devices:"
        ls -la /dev/video* 2>/dev/null || echo "None found"
        exit 1
    fi
    
    # Verify it's the IR camera (greyscale format)
    local format=$(v4l2-ctl -d /dev/video2 --get-fmt-video 2>/dev/null | grep "Pixel Format" || echo "")
    if [[ "$format" == *"GREY"* ]]; then
        log_ok "IR camera detected at /dev/video2 (Greyscale format)"
        return 0
    else
        log_warn "Device at /dev/video2 may not be IR camera"
        log_info "Format: $format"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi
}


configure_howdy() {
    log_info "Configuring howdy for Zephyrus G16..."
    
    local config_file="/etc/howdy/config.ini"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "howdy config not found at $config_file"
        log_info "Expected location: /etc/howdy/config.ini"
        exit 1
    fi
    
    # Backup original config
    if [[ ! -f "${config_file}.backup" ]]; then
        cp "$config_file" "${config_file}.backup"
        log_ok "Config backed up to ${config_file}.backup"
    fi
    
    log_info "Applying optimized settings for Intel Arc iGPU + IR camera..."
    
    # ===========================================
    # [core] section
    # ===========================================
    
    # detection_notice: Don't spam terminal during auth attempts
    sed -i 's|^detection_notice.*|detection_notice = false|' "$config_file"
    
    # timeout_notice: Show notice when timeout occurs (helpful for debugging)
    sed -i 's|^timeout_notice.*|timeout_notice = true|' "$config_file"
    
    # no_confirmation: Keep confirmation for successful auth (security awareness)
    sed -i 's|^no_confirmation.*|no_confirmation = false|' "$config_file"
    
    # suppress_unknown: Don't silently fail - show error if face unknown
    sed -i 's|^suppress_unknown.*|suppress_unknown = false|' "$config_file"
    
    # abort_if_ssh: Security - don't allow face auth over SSH
    sed -i 's|^abort_if_ssh.*|abort_if_ssh = true|' "$config_file"
    
    # abort_if_lid_closed: Security - don't auth with closed lid
    sed -i 's|^abort_if_lid_closed.*|abort_if_lid_closed = true|' "$config_file"
    
    # use_cnn: Enable CNN model - your Intel Arc iGPU can handle this
    # CNN is more accurate than HOG, especially for IR cameras
    sed -i 's|^use_cnn.*|use_cnn = true|' "$config_file"
    log_info "  ✓ CNN detection: enabled (Intel Arc GPU accelerated)"
    
    # workaround: Use 'input' for better UX with GNOME
    # Sends enter keypress after timeout instead of waiting
    sed -i 's|^workaround.*|workaround = input|' "$config_file"
    log_info "  ✓ Workaround: input (auto-enter on timeout)"
    
    # ===========================================
    # [video] section
    # ===========================================
    
    # certainty: 3.5 is balanced (lower = stricter, max recommended is 5)
    # For IR camera, 3.5-4.0 works well
    sed -i 's|^certainty.*|certainty = 3.5|' "$config_file"
    log_info "  ✓ Certainty: 3.5 (balanced security)"
    
    # timeout: 4 seconds is reasonable for IR camera
    sed -i 's|^timeout.*|timeout = 4|' "$config_file"
    log_info "  ✓ Timeout: 4 seconds"
    
    # device_path: Your IR camera
    sed -i 's|^device_path.*|device_path = /dev/video2|' "$config_file"
    log_info "  ✓ Device: /dev/video2 (IR camera)"
    
    # max_height: 320 is good balance of speed/accuracy
    # Your IR camera is 400px, so 320 is reasonable downscale
    sed -i 's|^max_height.*|max_height = 320|' "$config_file"
    log_info "  ✓ Max height: 320 (balanced speed/accuracy)"
    
    # frame_width/height: Set to IR camera native resolution
    # -1 would pick the largest (1080p RGB), we want the IR specific
    sed -i 's|^frame_width.*|frame_width = 640|' "$config_file"
    sed -i 's|^frame_height.*|frame_height = 400|' "$config_file"
    log_info "  ✓ Resolution: 640x400 (IR camera native)"
    
    # dark_threshold: IR works in low light, 50 is reasonable
    # Lower = more dark frames ignored (stricter)
    sed -i 's|^dark_threshold.*|dark_threshold = 50|' "$config_file"
    log_info "  ✓ Dark threshold: 50 (good for IR)"
    
    # recording_plugin: opencv is default and works well
    # ffmpeg can help with grayscale issues if needed
    sed -i 's|^recording_plugin.*|recording_plugin = opencv|' "$config_file"
    
    # force_mjpeg: false for IR camera (uses GREY format, not MJPEG)
    sed -i 's|^force_mjpeg.*|force_mjpeg = false|' "$config_file"
    
    # exposure: -1 = auto (let camera handle it)
    sed -i 's|^exposure.*|exposure = -1|' "$config_file"
    
    # device_fps: -1 = auto, but IR camera is 15fps
    # Setting explicitly can help IR emitter sync
    sed -i 's|^device_fps.*|device_fps = 15|' "$config_file"
    log_info "  ✓ FPS: 15 (IR camera native)"
    
    # rotate: 0 = landscape only (laptop camera is fixed landscape)
    sed -i 's|^rotate.*|rotate = 0|' "$config_file"
    
    # ===========================================
    # [snapshots] section
    # ===========================================
    
    # save_failed: Enable for security auditing (see who tried to auth)
    sed -i 's|^save_failed.*|save_failed = true|' "$config_file"
    log_info "  ✓ Save failed attempts: enabled (security audit)"
    
    # save_successful: Disable to save disk space
    sed -i 's|^save_successful.*|save_successful = false|' "$config_file"
    
    # ===========================================
    # [rubberstamps] section - extra verification
    # ===========================================
    
    # enabled: Keep disabled for now (adds latency)
    # Can enable 'nod' detection for extra security later
    sed -i 's|^enabled.*|enabled = false|' "$config_file"
    
    # ===========================================
    # [debug] section
    # ===========================================
    
    # end_report: Disable (can break some GTK apps)
    sed -i 's|^end_report.*|end_report = false|' "$config_file"
    
    log_ok "howdy configured optimally for Zephyrus G16"
    echo
    log_info "Config file: $config_file"
    log_info "Key settings:"
    echo "  • CNN model enabled (Intel Arc GPU accelerated)"
    echo "  • IR camera at native 640x400 @ 15fps"
    echo "  • Certainty 3.5 (adjust 3.0-4.0 based on experience)"
    echo "  • Failed auth snapshots saved to /var/log/howdy/snapshots"
    echo
    log_warn "Tuning tips:"
    echo "  • If auth fails often: increase certainty (4.0)"
    echo "  • If too loose (false positives): decrease certainty (3.0)"
    echo "  • If lighting issues: adjust dark_threshold (40-70)"
}

configure_pam_sudo() {
    log_info "Configuring PAM for sudo..."
    
    local pam_file="/etc/pam.d/sudo"
    local howdy_line="auth       sufficient   pam_howdy.so"
    
    # Check if already configured
    if grep -q "howdy" "$pam_file" 2>/dev/null; then
        log_ok "PAM sudo already configured for howdy"
        return 0
    fi
    
    # Backup
    cp "$pam_file" "${pam_file}.backup"
    
    # Add howdy as first auth method (sufficient = if it passes, skip password)
    sed -i "1a $howdy_line" "$pam_file"
    
    log_ok "PAM sudo configured - face auth will be tried first"
    log_info "New /etc/pam.d/sudo:"
    cat "$pam_file"
}

configure_pam_gdm() {
    log_info "Configuring PAM for GDM login..."
    
    local pam_file="/etc/pam.d/gdm-password"
    local howdy_line="auth       sufficient   pam_howdy.so"
    
    # Check if already configured
    if grep -q "howdy" "$pam_file" 2>/dev/null; then
        log_ok "PAM GDM already configured for howdy"
        return 0
    fi
    
    # Backup
    cp "$pam_file" "${pam_file}.backup"
    
    # Add howdy before the include line
    sed -i "/^auth.*include/i $howdy_line" "$pam_file"
    
    log_ok "PAM GDM configured - face auth at login screen"
    log_info "New /etc/pam.d/gdm-password:"
    cat "$pam_file"
}

configure_pam_system_auth() {
    log_info "Configuring PAM system-auth (affects polkit, etc.)..."
    
    local pam_file="/etc/pam.d/system-auth"
    local howdy_line="auth       sufficient   pam_howdy.so"
    
    # Check if already configured
    if grep -q "howdy" "$pam_file" 2>/dev/null; then
        log_ok "PAM system-auth already configured for howdy"
        return 0
    fi
    
    # Backup
    cp "$pam_file" "${pam_file}.backup"
    
    # Add howdy after pam_faillock preauth but before pam_unix
    sed -i "/pam_faillock.so.*preauth/a $howdy_line" "$pam_file"
    
    log_ok "PAM system-auth configured"
}

add_face_model() {
    log_info "Adding your face to howdy..."
    log_warn "This requires good lighting and the IR camera"
    
    echo
    echo "Position your face in front of the camera and press Enter..."
    read -r
    
    # howdy add requires root
    howdy add
    
    log_ok "Face model added"
}

test_howdy() {
    log_info "Testing howdy face recognition..."
    
    echo "Look at the camera..."
    if howdy test; then
        log_ok "Face recognition working!"
    else
        log_warn "Test failed - you may need to re-add your face or adjust settings"
    fi
}

show_usage() {
    cat << 'EOF'
IR Authentication Configuration for Zephyrus G16

Prerequisites:
  1. Install howdy: yay -S howdy
  2. Run this script with sudo

Usage: sudo ./ir-auth-setup.sh [command]

Commands:
  configure   Configure howdy for Zephyrus G16 IR camera
  pam         Configure PAM for sudo, login, and polkit
  add         Add your face to howdy
  test        Test face recognition
  status      Show current configuration status
  all         Run full setup (configure + pam + add)

After setup, use these commands:
  sudo howdy list              List enrolled faces
  sudo howdy add               Add another face model
  sudo howdy remove <id>       Remove a face
  sudo howdy clear             Remove all faces
  sudo howdy test              Test recognition
  sudo howdy config            Edit config manually
  sudo howdy disable 1         Temporarily disable (0=enable)

Configuration tips:
  - IR camera works in low light, but not pitch black
  - If auth fails too often: increase certainty (edit config, set to 4.0)
  - If auth too loose: decrease certainty (set to 3.0)
  - CNN mode uses Intel Arc GPU for better accuracy
EOF
}

show_status() {
    echo "=== IR Authentication Status ==="
    echo
    
    # Hardware
    echo "Hardware:"
    echo "  Model: ASUS ROG Zephyrus G16 (GU605CX)"
    echo "  CPU: Intel Core Ultra 9 285H (Arrow Lake)"
    echo "  iGPU: Intel Arc Graphics (Xe LPG)"
    if [[ -e /dev/video2 ]]; then
        echo "  IR camera: /dev/video2 ✓"
        v4l2-ctl -d /dev/video2 --get-fmt-video 2>/dev/null | grep -E "Width|Pixel|Frames" | sed 's/^/    /'
    else
        echo "  IR camera: ✗ NOT FOUND"
    fi
    echo
    
    # howdy
    echo "howdy:"
    if command -v howdy &>/dev/null; then
        echo "  Installed: ✓ yes"
        howdy --version 2>/dev/null | sed 's/^/    /' || true
        
        if [[ -f /etc/howdy/config.ini ]]; then
            local device=$(grep "^device_path" /etc/howdy/config.ini 2>/dev/null | cut -d= -f2 | tr -d ' ')
            local use_cnn=$(grep "^use_cnn" /etc/howdy/config.ini 2>/dev/null | cut -d= -f2 | tr -d ' ')
            local certainty=$(grep "^certainty" /etc/howdy/config.ini 2>/dev/null | cut -d= -f2 | tr -d ' ')
            
            echo "  Configuration:"
            echo "    device_path: ${device:-not set}"
            echo "    use_cnn: ${use_cnn:-false} $([ "$use_cnn" = "true" ] && echo "(Intel Arc GPU enabled)" || echo "(CPU only)")"
            echo "    certainty: ${certainty:-default}"
        fi
        
        echo "  Faces enrolled:"
        if [[ $EUID -eq 0 ]]; then
            howdy list 2>/dev/null | sed 's/^/    /' || echo "    none"
        else
            echo "    (run with sudo to see list)"
        fi
    else
        echo "  Installed: ✗ no"
        echo "  → Install: yay -S howdy"
    fi
    echo
    
    # PAM
    echo "PAM Configuration:"
    for f in sudo gdm-password system-auth; do
        if grep -q "howdy" "/etc/pam.d/$f" 2>/dev/null; then
            echo "  $f: ✓ configured"
        else
            echo "  $f: ✗ not configured"
        fi
    done
    echo
    
    # Quick test
    if command -v howdy &>/dev/null && [[ $EUID -eq 0 ]]; then
        echo "Quick test (press Ctrl+C to skip):"
        echo -n "  "
        howdy test 2>&1 | head -1 || true
    fi
}

main() {
    case "${1:-help}" in
        configure)
            check_root
            check_howdy_installed
            detect_ir_camera
            configure_howdy
            ;;
        pam)
            check_root
            check_howdy_installed
            configure_pam_sudo
            configure_pam_gdm
            configure_pam_system_auth
            ;;
        add)
            check_root
            check_howdy_installed
            add_face_model
            ;;
        test)
            check_root
            check_howdy_installed
            test_howdy
            ;;
        status)
            show_status
            ;;
        all)
            check_root
            check_howdy_installed
            detect_ir_camera
            configure_howdy
            configure_pam_sudo
            configure_pam_gdm
            configure_pam_system_auth
            add_face_model
            test_howdy
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
