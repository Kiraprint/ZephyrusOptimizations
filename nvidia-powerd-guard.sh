#!/usr/bin/env bash
# nvidia-powerd-guard.sh — guard wrapper for nvidia-powerd.
#
# nvidia-powerd (Dynamic Boost) attaches to the GPU via NVML/RM at startup.
# In cardwire integrated mode the dGPU's sysfs/dev nodes are hidden by the
# eBPF block (ENOENT), so NVML attach can hang (freeze at 14:13:21). cardwire
# restarts nvidia-powerd on every mode switch, so the restart can race with a
# blocked/hidden GPU. This wrapper makes such restarts safe no-ops.
# (Mechanism corrected 2026-08-10 — see docs/NVIDIA_D3COLD_REINVESTIGATION.md:
# no real bus removal occurs; the hiding is eBPF.)
#
# Installed via systemd drop-in:
#   /etc/systemd/system/nvidia-powerd.service.d/guard.conf
#     [Service]
#     ExecStart=
#     ExecStart=/usr/local/bin/nvidia-powerd-guard
set -uo pipefail

if [[ ! -d "/sys/bus/pci/devices/0000:01:00.0" ]]; then
    # dGPU not on the bus — do not start nvidia-powerd; exit cleanly.
    # The systemd drop-in sets RestartPreventExitStatus=0, so this clean
    # exit is never respawned even if other drop-ins force Restart=always.
    exit 0
fi

exec /usr/bin/nvidia-powerd "$@"
