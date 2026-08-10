#!/usr/bin/env bash
# dgpu-cleanup.sh — run by udev when the dGPU disappears from the bus.
#
# The ASUS platform removes the dGPU subtree on D3cold entry (power cut).
# This leaves the nvidia driver loaded against a dead device ("zombie"),
# which makes later NVML/RM access (nvidia-powerd attach, nvidia-smi) hang
# the system. This script makes the D3cold power-off clean:
#   1. stop nvidia-powerd (it would attach to the dead device)
#   2. unload the nvidia kernel modules (no clients at boot → succeeds)
#
# If modules are still in use (session apps), unloading fails and the zombie
# remains, but nvidia-powerd stays stopped, so nothing can hang on it.
set -uo pipefail

# Stop first: nvidia-powerd holds RM references to the removed device
systemctl stop nvidia-powerd.service 2>/dev/null || true

# Unload in dependency order (best effort)
for mod in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
    if lsmod | grep -q "^${mod} "; then
        modprobe -r "$mod" 2>/dev/null || true
    fi
done

exit 0
