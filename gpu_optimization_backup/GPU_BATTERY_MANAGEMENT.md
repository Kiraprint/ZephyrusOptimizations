# GPU Battery Management

**Status:** Installed and configured

## What it does

Automatically disables/enables dGPU based on power state:

- **On Battery**: Unloads NVIDIA modules → dGPU in D3cold (0W)
- **On AC**: Loads NVIDIA modules + starts nvidia-powerd → Full performance

## Files

1. `/usr/local/bin/gpu-battery-management.sh` - Main script
2. `/etc/udev/rules.d/99-gpu-battery.rules` - Udev triggers

## Expected battery life improvement

**Before (dGPU always on):**
- 8W idle + system power = ~15-20W total
- ~4-5 hours battery

**After (dGPU off on battery):**
- System power only = ~5-10W total
- ~8-10 hours battery (estimated 2x improvement!)

## Manual testing

**Disable dGPU immediately:**
```bash
sudo /usr/local/bin/gpu-battery-management.sh battery
```

**Enable dGPU immediately:**
```bash
sudo /usr/local/bin/gpu-battery-management.sh ac
```

## Verification

**Check current GPU state:**
```bash
# On battery (should be empty or show no NVIDIA):
lsmod | grep nvidia

# On AC (should show nvidia modules):
lsmod | grep nvidia

# Check power:
nvidia-smi  # Should fail on battery
```

## Automatic behavior

After plugging in/out, udev will automatically:
1. Detect power supply change
2. Call the script with battery/ac parameter
3. Load/unload NVIDIA modules
4. Start/stop nvidia-powerd

**Delay:** Usually 1-2 seconds

## Reverting

If you want to disable this feature:
```bash
sudo rm /etc/udev/rules.d/99-gpu-battery.rules
sudo rm /usr/local/bin/gpu-battery-management.sh
sudo udevadm control --reload
```

## Known issues

- **Gaming on battery:** dGPU will be disabled. Manual re-enable needed:
  ```bash
  sudo /usr/local/bin/gpu-battery-management.sh ac
  ```

- **Module reload delay:** First CUDA command might take 1-2 seconds when reconnecting to AC

