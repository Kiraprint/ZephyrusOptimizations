#!/bin/bash
# Run this after reboot to verify Optimus setup

echo "=== GPU Status Check ==="
echo ""

echo "1. MUX Mode:"
asusctl armoury get gpu_mux_mode 2>&1 | grep current

echo ""
echo "2. dGPU Power State:"
echo -n "   Status: "
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status

echo ""
echo "3. dGPU Power Draw:"
nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv

echo ""
echo "4. Processes Using dGPU:"
nvidia-smi pmon -c 1 2>&1 | grep -v "^#" || echo "   None (good!)"

echo ""
echo "5. Desktop Renderer:"
glxinfo 2>&1 | grep "OpenGL renderer"

echo ""
echo "6. Environment Variables:"
echo "   KWIN_DRM_DEVICES: $KWIN_DRM_DEVICES"
echo "   __GLX_VENDOR_LIBRARY_NAME: $__GLX_VENDOR_LIBRARY_NAME"

echo ""
echo "=== Expected Results ==="
echo "✓ MUX Mode: [(0),1]"
echo "✓ dGPU Status: suspended"
echo "✓ dGPU Power: 0-2W"
echo "✓ Processes: None"
echo "✓ Renderer: Intel"
