# Optimus Mode Configuration

**Date:** 2026-03-25  
**Status:** MUX switched to Optimus (mode 0) ✅

## Card Assignment

- **card1**: Intel Arc iGPU (0x8086)
- **card2**: NVIDIA RTX 5090 dGPU (0x10de)
- **card0**: Does not exist (kernel skipped, normal)

## Why card1 not card0?

The card number is just a kernel identifier, **NOT** a priority indicator.
- Apps don't automatically use "card0"
- Desktop compositor chooses based on environment variables
- We explicitly tell KDE to use card1 (Intel) via `KWIN_DRM_DEVICES`

## KDE/Plasma Configuration

### Files Created:

1. **~/.config/plasma-workspace/env/kwin_igpu.sh**
   - Runs at KDE startup
   - Sets environment variables for compositor

2. **~/.config/environment.d/kwin_igpu.conf**
   - Systemd user environment
   - Applied to all user services

### Environment Variables Set:

```bash
KWIN_DRM_DEVICES=/dev/dri/card1:/dev/dri/card2  # Intel first
__GLX_VENDOR_LIBRARY_NAME=mesa                   # Use Mesa, not NVIDIA
MESA_LOADER_DRIVER_OVERRIDE=iris                 # Intel driver
```

## Expected Behavior After Reboot

### Desktop (idle):
- Compositor uses Intel iGPU
- dGPU enters D3cold (suspended)
- Power draw: ~0-2W

### When running NVIDIA apps:
- App uses `__NV_PRIME_RENDER_OFFLOAD=1`
- dGPU wakes up automatically
- After app closes, dGPU suspends again

## Verification Commands

```bash
# Check MUX mode
asusctl armoury get gpu_mux_mode
# Should show: [(0),1] - mode 0 active

# Check dGPU power state
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
# Should show: suspended

# Check what's using dGPU
nvidia-smi pmon
# Should show: no processes

# Check desktop renderer
glxinfo | grep "OpenGL renderer"
# Should show: Intel (not NVIDIA/zink)
```

## Troubleshooting

If dGPU still active after logout/login:
1. Check environment loaded: `echo $KWIN_DRM_DEVICES`
2. Check compositor: `nvidia-smi pmon` (should be empty)
3. Force test Intel rendering: `DRI_PRIME=0 glxinfo | grep renderer`

## Battery Life Impact

**Before (MUX=1, dGPU Direct):**
- Display wired through dGPU
- Minimum ~7-10W idle
- 3-4 hours battery (estimate)

**After (MUX=0, Optimus, working correctly):**
- Display via iGPU
- dGPU suspended: ~0-2W
- 5-7 hours battery (estimate)

**Savings: ~2-3 hours extra battery life** 🎉

---

## Files Modified

- `~/.config/kwinrc` (OpenGLPlatformInterface=egl)
- `~/.config/plasma-workspace/env/kwin_igpu.sh` (new)
- `~/.config/environment.d/kwin_igpu.conf` (new)

## Reverting to dGPU Direct

If you need maximum gaming performance:

```bash
asusctl armoury set gpu_mux_mode 1
sudo reboot
```

Note: Requires reboot, will reduce battery life.

