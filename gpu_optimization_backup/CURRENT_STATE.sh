#!/bin/bash
# Check current GPU state
# Run this anytime to see what's active

echo "=== GPU Information ==="
nvidia-smi --query-gpu=name,driver_version,power.draw,power.limit,power.max_limit,clocks.gr,clocks.mem,pstate --format=csv

echo ""
echo "=== Power Management ==="
echo "PCIe control: $(cat /sys/bus/pci/devices/0000:01:00.0/power/control)"
echo "Runtime status: $(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status)"
echo "D3 support:"
cat /proc/driver/nvidia/gpus/0000:01:00.0/power | grep -i "runtime d3"

echo ""
echo "=== ASUS Settings ==="
asusctl armoury get nv_tgp 2>/dev/null | grep -v "Multiple"
asusctl armoury get nv_dynamic_boost 2>/dev/null | grep -v "Multiple"
asusctl armoury get gpu_mux_mode 2>/dev/null | grep -v "Multiple"
asusctl armoury get dgpu_disable 2>/dev/null | grep -v "Multiple"

echo ""
echo "=== Platform Profile ==="
cat /sys/firmware/acpi/platform_profile

echo ""
echo "=== Udev Rules ==="
if [ -f /etc/udev/rules.d/80-nvidia-pm.rules ]; then
    echo "D3 power saving rule: ACTIVE"
else
    echo "D3 power saving rule: NOT PRESENT"
fi

echo ""
echo "=== PowerMizer Mode ==="
nvidia-settings -q GPUPowerMizerMode 2>/dev/null | grep "Attribute" || echo "nvidia-settings not available"

echo ""
echo "=== Locked Clocks ==="
nvidia-smi --query-gpu=clocks_event_reasons.gpu_idle,clocks_event_reasons.sw_power_cap --format=csv

