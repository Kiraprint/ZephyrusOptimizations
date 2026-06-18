# Final GPU Configuration

**Date:** 2026-03-25  
**Status:** Optimized for battery life + performance

---

## What Changed

### Removed
- ❌ `nvidia-drm.modeset=0` (was preventing proper power management)

### Added
- ✅ MUX mode 0 (Optimus)
- ✅ `DRI_PRIME=0` environment variable (forces Intel desktop)
- ✅ Battery management script (auto-disables dGPU on battery)
- ✅ Udev rule (triggers on AC plug/unplug)

---

## Current Configuration

### Kernel Parameters
```
quiet nowatchdog splash rw rootflags=subvol=/@ rd.luks.uuid=... root=... 
i915.enable_dpcd_backlight=1 
nvidia.NVreg_EnableBacklightHandler=0 
nvidia.NVreg_RegistryDwords=EnableBrightnessControl=0
```

### Environment Variables
- `DRI_PRIME=0` (use Intel for desktop)

### Power Management
- **On AC:** dGPU active, nvidia-powerd running
- **On Battery:** dGPU modules unloaded (0W)

---

## Expected Behavior

### Boot
- ⚠️ Boot logo will be **duplicated** (cosmetic issue only)
- Both Intel and NVIDIA framebuffers active during boot
- Normal once desktop loads

### Desktop (Idle)
| Power State | Display | dGPU Power | Desktop GPU | Modules Loaded |
|-------------|---------|------------|-------------|----------------|
| **On AC** | Intel | ~0-2W (suspended) | Intel | ✅ |
| **On Battery** | Intel | 0W (off) | Intel | ❌ |

### Under Load (ML/Gaming)
| Power State | dGPU Available | Max TDP | Notes |
|-------------|----------------|---------|-------|
| **On AC** | ✅ Yes | 110W | Firmware-limited (vBIOS: 175W) |
| **On Battery** | ❌ No | N/A | Modules unloaded for battery life |

---

## Battery Life Estimate

**Before optimization:**
- dGPU always active: 8-32W
- Total system: 15-40W
- Battery life: ~3-5 hours

**After optimization:**
- dGPU on battery: 0W
- Total system: ~7-12W  
- Battery life: **~8-10 hours** (2x improvement!)

---

## Files Created/Modified

### System Files
1. `/boot/limine.conf` - Kernel parameters
2. `/usr/local/bin/gpu-battery-management.sh` - Battery script
3. `/etc/udev/rules.d/99-gpu-battery.rules` - Power event trigger

### User Files  
4. `~/.config/environment.d/kwin_igpu.conf` - DRI_PRIME=0
5. `~/.config/plasma-workspace/env/kwin_igpu.sh` - Desktop GPU preference

### Backup Location
`~/Code/ZephyrusOptimizations/gpu_optimization_backup/`

---

## Manual Controls

### Force dGPU OFF (battery mode):
```bash
sudo /usr/local/bin/gpu-battery-management.sh battery
```

### Force dGPU ON (AC mode):
```bash
sudo /usr/local/bin/gpu-battery-management.sh ac
```

### Check current status:
```bash
# Check if modules loaded
lsmod | grep nvidia

# Check power draw (if modules loaded)
nvidia-smi --query-gpu=power.draw --format=csv

# Check GPU being used
glxinfo | grep "OpenGL renderer"
```

---

## Known Issues/Tradeoffs

### ✅ Fixed
- Desktop now uses Intel iGPU (battery efficient)
- dGPU properly suspends when idle on AC
- dGPU completely off on battery
- nvidia-powerd doesn't prevent suspend anymore

### ⚠️ Cosmetic Issues
- Boot logo duplicated (Intel + NVIDIA framebuffers)
- Not fixable without breaking power management

### ❌ Hardware Limitations
- Max TDP: 110W (not 175W) - ASUS firmware locked
- Can't change via software
- Windows might have hit 140W with different BIOS version

---

## Reverting Changes

### To revert everything:
```bash
# Remove battery management
sudo rm /etc/udev/rules.d/99-gpu-battery.rules
sudo rm /usr/local/bin/gpu-battery-management.sh
sudo udevadm control --reload

# Remove environment variables
rm ~/.config/environment.d/kwin_igpu.conf
rm ~/.config/plasma-workspace/env/kwin_igpu.sh

# Switch back to dGPU Direct (optional)
asusctl armoury set gpu_mux_mode 1
sudo reboot
```

---

## Summary

**Optimized for:** Battery life + performance when needed

**Best for:** Users who:
- Want long battery life
- Use dGPU only on AC power
- Don't mind cosmetic boot logo issue
- Need full dGPU performance for ML/gaming on AC

**Not recommended for:** Users who need dGPU on battery (gaming on the go)

