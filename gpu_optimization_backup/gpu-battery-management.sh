#!/bin/bash
# GPU power management based on AC/battery state
# This script runs when power state changes

POWER_STATE="$1"

if [ "$POWER_STATE" = "battery" ]; then
    echo "Battery mode: Disabling dGPU completely"
    
    # Stop nvidia-powerd
    systemctl stop nvidia-powerd.service
    
    # Remove NVIDIA modules to force D3cold
    modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia
    
    echo "dGPU disabled for battery savings"
    
elif [ "$POWER_STATE" = "ac" ]; then
    echo "AC mode: Enabling dGPU"
    
    # Load NVIDIA modules
    modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm
    
    # Start nvidia-powerd
    systemctl start nvidia-powerd.service
    
    echo "dGPU enabled for performance"
fi
