#!/bin/bash
#
# Howdy Face Recognition Setup for KDE
# Automates installation and configuration of Howdy for KDE login/lock screen
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should NOT be run as root. Run as normal user with sudo privileges."
        exit 1
    fi
}

# Function to detect IR camera
detect_ir_camera() {
    local ir_device=""
    
    for device in /dev/video*; do
        if [[ -c "$device" ]]; then
            formats=$(v4l2-ctl -d "$device" --list-formats-ext 2>/dev/null | grep -i "GREY\|Y16" || true)
            if [[ -n "$formats" ]]; then
                ir_device="$device"
                break
            fi
        fi
    done
    
    if [[ -z "$ir_device" ]]; then
        ir_device="/dev/video0"
    fi
    
    echo "$ir_device"
}

# Function to check if Howdy is already installed
check_howdy_installed() {
    if pacman -Qi howdy &>/dev/null || pacman -Qi howdy-bin &>/dev/null || pacman -Qi howdy-git &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to install Howdy
install_howdy() {
    if check_howdy_installed; then
        print_success "Howdy is already installed"
        return 0
    fi
    
    print_info "Installing Howdy from AUR..."
    
    # Check if paru is available
    if command -v paru &>/dev/null; then
        paru -S --noconfirm howdy-bin
    elif command -v yay &>/dev/null; then
        yay -S --noconfirm howdy-bin
    else
        print_error "Neither paru nor yay found. Please install an AUR helper first."
        exit 1
    fi
    
    print_success "Howdy installed successfully"
}

# Function to configure Howdy
configure_howdy() {
    print_info "Configuring Howdy..."
    
    local ir_camera=$1
    local config_file="/etc/howdy/config.ini"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Howdy config file not found at $config_file"
        exit 1
    fi
    
    # Backup original config
    sudo cp "$config_file" "$config_file.backup"
    print_info "Config backed up to $config_file.backup"
    
    # Create a Python script to safely edit the config
    cat > /tmp/configure_howdy.py << 'PYEOF'
import configparser
import sys

config_file = sys.argv[1]
ir_camera = sys.argv[2]

config = configparser.ConfigParser()
config.read(config_file)

# Update device_path in [core] section
if not config.has_section('core'):
    config.add_section('core')
config.set('core', 'device_path', ir_camera)

# Set other recommended settings if they exist
if config.has_option('core', 'no_confirmation'):
    config.set('core', 'no_confirmation', 'false')
if config.has_option('core', 'abort_if_ssh'):
    config.set('core', 'abort_if_ssh', 'true')
if config.has_option('core', 'abort_if_lid_closed'):
    config.set('core', 'abort_if_lid_closed', 'true')

# Write back
with open(config_file, 'w') as f:
    config.write(f)
PYEOF
    
    # Run the Python script with sudo (suppress output)
    sudo python3 /tmp/configure_howdy.py "$config_file" "$ir_camera" >/dev/null 2>&1
    
    # Clean up
    rm /tmp/configure_howdy.py
    
    print_success "Howdy configured to use $ir_camera"
}

# Function to add face model
add_face_model() {
    print_info "Adding face model..."
    echo ""
    print_warning "Please look at your camera. Press Enter when ready..."
    read -r
    
    echo ""
    print_info "Capturing your face (model: default)..."
    sudo howdy add -y default
    
    echo ""
    print_info "Would you like to add another model for different angles? (y/n)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_info "Capturing second model (model: angle2)..."
        sudo howdy add -y angle2
    fi
    
    print_success "Face model(s) added successfully"
}

# Function to test Howdy
test_howdy() {
    print_info "Testing Howdy facial recognition..."
    echo ""
    print_warning "Please look at your camera..."
    echo ""
    
    sudo howdy test
    
    echo ""
    print_info "Did the test succeed? (y/n)"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_warning "Face recognition test failed or needs adjustment"
        print_info "You can adjust certainty in config: sudo howdy config"
        print_info "Lower value = more strict (2.0-3.5), Higher = more lenient (3.5-5.0)"
    fi
}

# Function to configure PAM
configure_pam() {
    print_info "Configuring PAM for KDE integration..."
    
    local pam_line="auth    sufficient    pam_howdy.so"
    
    # Configure KDE lock screen
    if [[ -f /etc/pam.d/kde ]]; then
        if ! grep -q "howdy" /etc/pam.d/kde; then
            print_info "Adding Howdy to KDE lock screen..."
            sudo sed -i "1i $pam_line" /etc/pam.d/kde
            print_success "KDE lock screen configured"
        else
            print_warning "Howdy already configured in /etc/pam.d/kde"
        fi
    else
        print_warning "/etc/pam.d/kde not found, skipping KDE lock screen config"
    fi
    
    # Configure SDDM login
    if [[ -f /etc/pam.d/sddm ]]; then
        if ! grep -q "howdy" /etc/pam.d/sddm; then
            print_info "Adding Howdy to SDDM login..."
            sudo sed -i "1i $pam_line" /etc/pam.d/sddm
            print_success "SDDM login configured"
        else
            print_warning "Howdy already configured in /etc/pam.d/sddm"
        fi
    else
        print_warning "/etc/pam.d/sddm not found, skipping SDDM config"
    fi
    
    # Ask about sudo configuration
    echo ""
    print_info "Would you like to enable Howdy for sudo authentication? (y/n)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        if [[ -f /etc/pam.d/sudo ]]; then
            if ! grep -q "howdy" /etc/pam.d/sudo; then
                sudo sed -i "1i $pam_line" /etc/pam.d/sudo
                print_success "Sudo authentication configured"
            else
                print_warning "Howdy already configured in /etc/pam.d/sudo"
            fi
        fi
    fi
    
    print_success "PAM configuration completed"
}

# Function to setup IR emitter (for ASUS laptops)
setup_ir_emitter() {
    print_info "Checking if IR emitter setup is needed..."
    
    local laptop_model=$(sudo dmidecode -s system-product-name 2>/dev/null || echo "Unknown")
    
    if [[ "$laptop_model" =~ "ROG" ]] || [[ "$laptop_model" =~ "Zephyrus" ]]; then
        print_info "ASUS ROG/Zephyrus laptop detected: $laptop_model"
        print_info "Would you like to install chicony-ir-toggle for IR emitter control? (y/n)"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            print_info "Installing chicony-ir-toggle..."
            if command -v paru &>/dev/null; then
                paru -S --noconfirm chicony-ir-toggle-git
            elif command -v yay &>/dev/null; then
                yay -S --noconfirm chicony-ir-toggle-git
            fi
            
            sudo systemctl enable --now chicony-ir-toggle
            print_success "IR emitter service enabled"
        fi
    else
        print_info "Not an ASUS ROG laptop, skipping IR emitter setup"
    fi
}

# Function to display final instructions
display_final_instructions() {
    echo ""
    echo "======================================"
    print_success "Howdy setup completed!"
    echo "======================================"
    echo ""
    print_info "Next steps:"
    echo "  1. Lock your screen (Ctrl+Alt+L) and test facial recognition"
    echo "  2. Log out and test SDDM login with facial recognition"
    echo ""
    print_info "Useful commands:"
    echo "  - Test recognition:      sudo howdy test"
    echo "  - Edit config:           sudo howdy config"
    echo "  - List face models:      sudo howdy list"
    echo "  - Add new model:         sudo howdy add"
    echo "  - Remove model:          sudo howdy remove <id>"
    echo "  - View logs:             sudo journalctl -u howdy -f"
    echo ""
    print_info "Troubleshooting:"
    echo "  - Too strict:  Increase 'certainty' value in config (4.0-5.0)"
    echo "  - Too loose:   Decrease 'certainty' value in config (2.0-3.0)"
    echo "  - Not working: Check camera with 'v4l2-ctl --list-devices'"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "======================================"
    echo "  Howdy Face Recognition Setup - KDE"
    echo "======================================"
    echo ""
    
    check_root
    
    # Check dependencies
    print_info "Checking dependencies..."
    if ! command -v v4l2-ctl &>/dev/null; then
        print_error "v4l-utils not found. Installing..."
        sudo pacman -S --noconfirm v4l-utils
    fi
    
    # Detect IR camera
    print_info "Detecting IR camera..."
    IR_CAMERA=$(detect_ir_camera)
    print_success "IR camera detected at $IR_CAMERA"
    
    # Install Howdy
    install_howdy
    
    # Configure Howdy
    configure_howdy "$IR_CAMERA"
    
    # Add face model
    add_face_model
    
    # Test Howdy
    test_howdy
    
    # Configure PAM
    configure_pam
    
    # Setup IR emitter if needed
    setup_ir_emitter
    
    # Display final instructions
    display_final_instructions
}

# Run main function
main
