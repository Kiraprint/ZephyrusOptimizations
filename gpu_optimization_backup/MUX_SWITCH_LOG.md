# MUX Switch to Optimus Mode - Change Log

**Date:** 2026-03-25  
**Action:** Switched from dGPU Direct (MUX=1) to Optimus (MUX=0)  
**Command:** `asusctl armoury set gpu_mux_mode 0`

## Status

- Setting queued: ✅ Yes
- Pending reboot: ✅ Yes (pending_reboot = 1)
- asusd confirmation: ✅ "gpu_mux_mode changed"

## What will happen after reboot

1. Display output will route through **iGPU**
2. dGPU can enter **D3cold** when not in use
3. Battery life should improve significantly
4. NVIDIA Optimus will handle GPU switching automatically

## Current state BEFORE reboot

- MUX mode firmware: Still 1 (dGPU Direct) - will apply on next boot
- dGPU power: Suspended (D3)
- Display: Still using dGPU (until reboot)

## After reboot

Expected changes:
- MUX mode: 0 (Optimus)
- dGPU idle power: ~0-2W (deep sleep)
- Display rendering: Via iGPU
- Discrete GPU usage: Automatic when needed

## Command to reboot

```bash
sudo reboot
```

