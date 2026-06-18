#!/bin/bash
# Complete restoration of all changes made during GPU optimization

echo "=== Starting Full Restoration ==="
echo ""

# 1. Remove battery management script
echo "1. Removing battery management..."
sudo rm -f /usr/local/bin/gpu-battery-management.sh
sudo rm -f /etc/udev/rules.d/99-gpu-battery.rules

# 2. Remove systemd services
echo "2. Removing systemd services..."
sudo systemctl disable gpu-battery-check.service 2>/dev/null
sudo systemctl stop gpu-battery-check.service 2>/dev/null
sudo rm -f /etc/systemd/system/gpu-battery-check.service
sudo systemctl daemon-reload

# 3. Remove environment overrides
echo "3. Removing environment variables..."
rm -f ~/.config/environment.d/kwin_igpu.conf
rm -f ~/.config/plasma-workspace/env/kwin_igpu.sh

# 4. Restore KWin config
echo "4. Restoring KWin config..."
kwriteconfig6 --file kwinrc --group Compositing --key OpenGLPlatformInterface --delete

# 5. Enable nvidia-powerd
echo "5. Re-enabling nvidia-powerd..."
sudo systemctl enable nvidia-powerd.service
sudo systemctl start nvidia-powerd.service

# 6. Restore MUX to dGPU Direct (mode 1)
echo "6. Switching MUX back to dGPU Direct..."
asusctl armoury set gpu_mux_mode 1

# 7. Reload udev
echo "7. Reloading udev..."
sudo udevadm control --reload

echo ""
echo "=== Restoration Complete ==="
echo ""
echo "Changes reverted:"
echo "  ✓ Battery management removed"
echo "  ✓ Environment variables removed"
echo "  ✓ Services removed"
echo "  ✓ MUX switched back to mode 1 (dGPU Direct)"
echo ""
echo "Next: REBOOT to restore everything"
echo "  sudo reboot"
echo ""
echo "After reboot, system will be back to original state"
