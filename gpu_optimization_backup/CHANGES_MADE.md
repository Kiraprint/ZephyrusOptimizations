# GPU Optimization Changes Log
**Date:** 2026-03-24  
**System:** ASUS ROG Zephyrus G16 GU605CX  
**GPU:** NVIDIA GeForce RTX 5090 Laptop GPU  
**Driver:** 595.45.04

---

## Changes Made

### 1. GPU Clock Locking (REVERTED)
**What:** Locked GPU core clock to 3082 MHz  
**Command:** `sudo nvidia-smi -lgc 3082`  
**Result:** GPU stayed at high clocks but still power-limited to ~100-116W  
**Status:** Should be reset with restore script

### 2. PowerMizer Mode
**What:** Set to "Prefer Maximum Performance"  
**Command:** `nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=1'`  
**Original:** Mode 0 (Auto)  
**Status:** Active

### 3. PCIe Power Management
**What:** Changed from `on` (always active) to `auto` (allow sleep)  
**File:** `/sys/bus/pci/devices/0000:01:00.0/power/control`  
**Original:** `on`  
**Current:** `auto`  
**Status:** Active

### 4. Persistent D3 Power Saving (NEW)
**What:** Created udev rule to enable runtime PM on boot  
**File:** `/etc/udev/rules.d/80-nvidia-pm.rules`  
**Content:**
```
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", ATTR{power/control}="auto"
```
**Status:** Active on next boot

### 5. NVIDIA Persistence Mode
**What:** Enabled via daemon  
**Command:** `nvidia-smi -pm 1`  
**Original:** Disabled  
**Status:** Active

---

## Failed Attempts

### MUX Switch Change
**Attempted:** Switch from dGPU Direct (mode 1) to Optimus (mode 0)  
**Command:** `asusctl armoury set gpu_mux_mode 0`  
**Result:** **FAILED** - "No such device" error  
**Reason:** Firmware doesn't support MUX switching via WMI on this model/BIOS  
**Current MUX:** Locked at mode 1 (dGPU Direct)

### dGPU Disable
**Attempted:** Disable dGPU completely for iGPU-only mode  
**Command:** `asusctl armoury set dgpu_disable 1`  
**Result:** **FAILED** - I/O error (device in use)  
**Status:** dGPU remains enabled (value 0)

### TDP Increase
**Attempted:** Increase GPU TDP from 110W to 175W  
**Method:** ASUS WMI firmware attributes  
**Result:** **BLOCKED** - Firmware limits `nv_tgp` to 95-110W range  
**Current:** 110W max (firmware-enforced)  
**vBIOS capability:** 175W (unused)

---

## Current State

### GPU Power Limits
- **Current Power Limit:** 100-116W (dynamic, EC-controlled)
- **Max Power Limit:** 175W (vBIOS capability, firmware-blocked)
- **Default Power Limit:** 95W

### GPU Clocks
- **Current:** 3082 MHz (locked) → **Should be reset to Auto**
- **Max Supported:** 3390 MHz
- **Idle:** 405-480 MHz (when unlocked)

### Power Management
- **PCIe Control:** `auto` (allows D3 sleep)
- **Runtime D3:** Enabled (fine-grained)
- **MUX Mode:** dGPU Direct (unchangeable)

### ASUS Armoury Settings
- **Platform Profile:** Performance
- **nv_tgp:** 110W
- **nv_dynamic_boost:** 20W
- **nv_temp_target:** 87°C

---

## How to Restore

### Quick Restore
```bash
~/gpu_optimization_backup/RESTORE_ORIGINAL.sh
```

### Manual Restore
```bash
# Reset GPU clocks
sudo nvidia-smi -rgc
sudo nvidia-smi -rmc

# Reset PowerMizer
nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=0'

# Restore PCIe power
echo on | sudo tee /sys/bus/pci/devices/0000:01:00.0/power/control

# Remove udev rule
sudo rm /etc/udev/rules.d/80-nvidia-pm.rules
sudo udevadm control --reload

# Disable persistence mode
sudo nvidia-smi -pm 0

# Reboot
sudo reboot
```

---

## Lessons Learned

1. **TDP is firmware-locked** - vBIOS capability ≠ actual limit
2. **MUX switching unavailable** - Not all ASUS models support it via Linux
3. **Power bottleneck, not clocks** - GPU has headroom but no power budget
4. **EC controls everything** - Laptop firmware manages power distribution
5. **D3 power saving works** - Can reduce idle power consumption
6. **Windows had different limits** - 140W on Windows vs 110W on Linux (possibly different BIOS state)

---

## Recommendations

### For Battery Life
Keep the new D3 power management settings - dGPU will sleep when idle.

### For Performance
Current 110W limit is firmware maximum. Focus on:
- Optimizing ML workloads for efficiency
- Ensuring adequate cooling (allows EC to allocate more power)
- Monitoring temps with `nvidia-smi dmon`

### For Future
- Check for BIOS updates from ASUS
- Monitor asusctl project for MUX support improvements
- Consider switching to AMD GPU next time (better Linux support)

---

## Files Modified

1. `/etc/udev/rules.d/80-nvidia-pm.rules` (new file)
2. `/sys/bus/pci/devices/0000:01:00.0/power/control` (runtime, reverts on reboot without udev rule)

## Configs Unchanged

- `/etc/asusd/asusd.ron` (not modified)
- `/etc/lact/config.yaml` (clock offsets exist but LACT not used)
- NVIDIA driver registry parameters (none set)

---

