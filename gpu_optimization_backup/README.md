# GPU Optimization Session Backup

This directory contains everything needed to restore your GPU settings to the state before optimization attempts.

## Quick Links

- **Restore everything:** `./RESTORE_ORIGINAL.sh`
- **Check current state:** `./CURRENT_STATE.sh`
- **See what changed:** `cat CHANGES_MADE.md`

## What Was Changed

1. GPU clocks locked to 3082 MHz (should be reset)
2. PowerMizer set to max performance
3. PCIe power management enabled (allows D3 sleep when idle)
4. Persistent udev rule created for D3 on boot
5. NVIDIA persistence mode enabled

## What Failed

- **MUX switching:** Firmware doesn't support it
- **TDP increase:** Locked at 110W by ASUS EC
- **dGPU disable:** Can't disable while in use

## Summary

You tried to:
- Increase 110W power limit → Blocked by firmware
- Switch to Optimus/iGPU mode → Hardware doesn't support it
- Force higher clocks → Works but power-limited anyway

The only useful change: **D3 power saving when idle** (reduces battery drain)

## Files in This Directory

```
gpu_optimization_backup/
├── README.md                  # This file
├── RESTORE_ORIGINAL.sh        # Undo all changes
├── CURRENT_STATE.sh           # Check what's active now
├── CHANGES_MADE.md            # Detailed changelog
└── session_backup.tar.gz      # Backup of modified files (if exists)
```

## Safe to Keep

The D3 power management is beneficial for battery life. If you want to keep it:
```bash
# Just reset the locked clocks
sudo nvidia-smi -rgc
```

## Full Restore

To go back to 100% original state:
```bash
./RESTORE_ORIGINAL.sh
sudo reboot
```

---

**Created:** 2026-03-24  
**System:** ASUS ROG Zephyrus G16 (RTX 5090 Mobile)
