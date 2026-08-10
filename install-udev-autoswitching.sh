#!/usr/bin/env bash
# =============================================================================
# install-udev-autoswitching.sh — Install automatic power switching
#
# This script installs udev rules and event handler for automatic
# power mode switching when AC adapter is plugged/unplugged.
#
# Usage:
#   sudo ./install-udev-autoswitching.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check root
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "=== Installing Zephyrus G16 Automatic Power Switching ==="
echo ""

# Ask about boot-time service
read -p "Install boot-time power management? (applies optimizations on boot) [Y/n] " -n 1 -r
echo ""
INSTALL_BOOT_SERVICE="yes"
if [[ $REPLY =~ ^[Nn]$ ]]; then
    INSTALL_BOOT_SERVICE="no"
fi
echo ""

# Step 1: Install event handler
echo "[1/4] Installing event handler to /usr/local/bin/..."
cp "$SCRIPT_DIR/zephyrus-power-event.sh" /usr/local/bin/zephyrus-power-event
chmod +x /usr/local/bin/zephyrus-power-event
echo "  ✓ Event handler installed"
echo ""

# Step 2: Create log file
echo "[2/4] Creating log file..."
touch /var/log/zephyrus-power.log
chmod 644 /var/log/zephyrus-power.log
echo "  ✓ Log file created: /var/log/zephyrus-power.log"
echo ""

# Step 3: Install udev rule
echo "[3/4] Installing udev rule to /etc/udev/rules.d/..."
cp "$SCRIPT_DIR/99-zephyrus-power.rules" /etc/udev/rules.d/
echo "  ✓ Udev rule installed"
echo ""

# Step 4: Reload udev
echo "[4/4] Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger
echo "  ✓ Udev reloaded"
echo ""

# Step 5: Install scx_lavd scheduler unit (used by AC mode)
echo "[5/6] Installing scx_lavd scheduler unit..."
cp "$SCRIPT_DIR/zephyrus-scx-lavd.service" /etc/systemd/system/
systemctl daemon-reload
echo "  ✓ scx_lavd unit installed (started on AC, stopped on battery)"
echo ""

# Step 6: Install boot service (optional)
if [[ "$INSTALL_BOOT_SERVICE" == "yes" ]]; then
    echo "[6/6] Installing boot-time power management service..."
    cp "$SCRIPT_DIR/zephyrus-power-boot.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable zephyrus-power-boot.service
    echo "  ✓ Boot service installed and enabled"
    echo ""
fi

echo "=== Installation Complete ==="
echo ""
echo "Automatic power switching is now active!"
echo ""
echo "What happens now:"
echo "  • When you unplug AC: Battery optimizations applied automatically"
echo "  • When you plug AC: AC/Performance mode applied automatically"
if [[ "$INSTALL_BOOT_SERVICE" == "yes" ]]; then
    echo "  • On boot: Detects current power state and applies appropriate settings"
fi
echo ""
echo "To monitor:"
echo "  tail -f /var/log/zephyrus-power.log"
echo ""
echo "To test manually:"
echo "  sudo /usr/local/bin/zephyrus-power-event 0  # Battery"
echo "  sudo /usr/local/bin/zephyrus-power-event 1  # AC"
echo ""
echo "To check current state:"
echo "  ./power-switch-unified.sh status"
echo ""
echo "To uninstall:"
echo "  sudo rm /etc/udev/rules.d/99-zephyrus-power.rules"
echo "  sudo rm /usr/local/bin/zephyrus-power-event"
if [[ "$INSTALL_BOOT_SERVICE" == "yes" ]]; then
    echo "  sudo systemctl disable zephyrus-power-boot.service"
    echo "  sudo rm /etc/systemd/system/zephyrus-power-boot.service"
fi
echo "  sudo udevadm control --reload-rules"
echo ""
