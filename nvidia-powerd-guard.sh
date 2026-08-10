#!/usr/bin/env bash
# nvidia-powerd-guard.sh — guard wrapper for nvidia-powerd.
#
# nvidia-powerd (Dynamic Boost) attaches to the GPU via NVML/RM at startup.
# If the dGPU was D3cold-removed from the bus (ASUS platform behavior),
# that attach can hang the whole system (freeze at 14:13:21). cardwire
# restarts nvidia-powerd on every mode switch, so the restart can race with
# an absent GPU. This wrapper makes such restarts safe no-ops.
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
