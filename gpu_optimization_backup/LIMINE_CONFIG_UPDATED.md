# Limine Configuration Updated

**Date:** 2026-03-25  
**Change:** Added `nvidia-drm.modeset=0` to all boot entries

## What was changed

Modified `/boot/limine.conf` to add the kernel parameter at the end of all CMDLINE entries.

**Before:**
```
cmdline: quiet nowatchdog splash rw ... nvidia.NVreg_RegistryDwords=EnableBrightnessControl=0
```

**After:**
```
cmdline: quiet nowatchdog splash rw ... nvidia.NVreg_RegistryDwords=EnableBrightnessControl=0 nvidia-drm.modeset=0
```

Applied to:
- ✅ Main kernel entries (linux-cachyos, linux-cachyos-rc)
- ✅ All snapshot entries
- ✅ Total: 10 CMDLINE entries

## What this does

- Disables NVIDIA DRM kernel mode setting
- Prevents NVIDIA from creating framebuffer at boot
- Fixes duplicated boot logo (only Intel framebuffer active)
- Does NOT disable NVIDIA GPU - only the display framebuffer

## Expected after reboot

- Boot logo: Single CachyOS image (no duplication)
- NVIDIA driver: Still loads normally
- dGPU: Should prefer Intel for rendering (Optimus)
- Power: dGPU should suspend when idle

## To revert

Remove ` nvidia-drm.modeset=0` from the end of any CMDLINE lines in `/boot/limine.conf` and reboot.

## Verification

After reboot, check:
```bash
cat /proc/cmdline | grep nvidia-drm
# Should show: nvidia-drm.modeset=0
```

