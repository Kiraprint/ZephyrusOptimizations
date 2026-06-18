#!/bin/bash
# Restore original GPU settings before optimization attempts
# Created: 2026-03-24

echo "=== Restoring original GPU settings ==="

echo ""
echo "1. Restoring GPU clock settings..."
sudo nvidia-smi -rgc  # Reset GPU clocks to default
sudo nvidia-smi -rmc  # Reset memory clocks to default

echo ""
echo "2. Disabling PowerMizer performance mode..."
nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=0' 2>/dev/null || echo "nvidia-settings not available"

echo ""
echo "3. Restoring PCIe power management to 'on' (always active)..."
echo on | sudo tee /sys/bus/pci/devices/0000:01:00.0/power/control

echo ""
echo "4. Removing persistent D3 power management udev rule..."
sudo rm -f /etc/udev/rules.d/80-nvidia-pm.rules
sudo udevadm control --reload

echo ""
echo "5. Checking NVIDIA persistence mode..."
sudo nvidia-smi -pm 0  # Disable persistence mode

echo ""
echo "6. Verifying current state..."
echo "GPU clocks:"
nvidia-smi --query-gpu=clocks.gr,clocks.mem,power.draw,pstate --format=csv

echo ""
echo "PCIe power control:"
cat /sys/bus/pci/devices/0000:01:00.0/power/control

echo ""
echo "=== Restore complete! ==="
echo "Original settings:"
echo "  - GPU clocks: Auto (GPU Boost managed)"
echo "  - PowerMizer: Auto (0)"
echo "  - PCIe power: Always on"
echo "  - Persistence mode: Disabled"
echo ""
echo "To reboot and ensure all changes take effect:"
echo "  sudo reboot"
