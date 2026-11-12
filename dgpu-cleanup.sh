#!/usr/bin/env bash
# dgpu-cleanup.sh — run by udev when the dGPU disappears from the bus.
#
# NOTE (2026-08-10): a kernel remove uevent for the dGPU never fires on this
# platform — cardwire's eBPF block only HIDES the device (no real removal),
# so this script is currently dead code. It is kept for the real-removal
# case (e.g. dgpu-switch eco rail cut), where the nvidia driver would be
# left against a dead device ("zombie") and later NVML/RM access
# (nvidia-powerd attach, nvidia-smi) could hang the system:
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
