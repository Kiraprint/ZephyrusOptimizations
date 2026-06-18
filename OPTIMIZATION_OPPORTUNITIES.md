# Additional Optimization Opportunities for ASUS ROG Zephyrus G16 (GU605CX)

## Hardware Summary
- **CPU**: Intel Core Ultra 9 285H (Arrow Lake, 16 cores: 6 P-cores + 8 E-cores + 2 LP E-cores)
- **iGPU**: Intel Arc Pro 130T (integrated)
- **dGPU**: NVIDIA RTX 5090 Max-Q
- **RAM**: 62 GB (61 GiB usable)
- **Storage**: 953.9GB NVMe (NTFS), 931.5GB NVMe (Btrfs/LUKS encrypted)
- **Battery**: ASUS A32-K55 (5452mAh, ~87Wh estimated)
- **Display**: Samsung ATNA60DL01-0 OLED (2560x1600, 48-240Hz VRR)

## Already Optimized ✅
- CPU power management (EPP, turbo, min_perf_pct)
- GPU runtime PM (D3cold sleep on idle)
- Display refresh rate switching (60/240Hz)
- Audio codec power-save
- USB autosuspend (with HID exclusion)
- Network power-save (WiFi, Bluetooth)
- PCIe ASPM (kernel-controlled)
- Kernel tunables (NMI, VM writeback)

## Potential Additional Optimizations

### 1. **Intel GPU Panel Self Refresh (PSR)** 🆕
- **Benefit**: ~5-10W power savings when static content displayed
- **Status**: Controlled by i915 driver (currently default)
- **Implementation**: May already be enabled, can be verified via `i915.enable_psr=1` boot param
- **Note**: Can cause screen flicker on some OLED displays - monitor carefully

### 2. **Intel GPU Frequency Scaling** 🆕
- **Benefit**: Reduce GPU power draw when not needed
- **Status**: Can be controlled via `/sys/class/drm/card*/device/power_dpm_state`
- **Implementation**: Set to "battery" on battery mode
- **Files**: `/sys/class/drm/card0/device/power_dpm_state`

### 3. **Scheduler Tuning for ARM/Hybrid CPUs** 🆕
- **Benefit**: Better E-core utilization, reduced P-core usage
- **Status**: Default scheduler should work well with Intel Thread Director
- **Note**: Arrow Lake's Thread Director already handles core selection optimally
- **Optional**: Reduce `kernel/sched_tunable_scaling` if load spikes observed

### 4. **Swap Configuration** 🆕
- **Current**: swappiness=150 (aggressive), zram0 (62GB compressed swap)
- **Opportunity**: 
  - Reduce swappiness to 10-30 for less thrashing
  - Monitor zram compression ratio
  - Consider PSI (Pressure Stall Information) tuning
  - Currently: 62GB swap with 0B usage (safe to reduce swappiness)

### 5. **Btrfs Specific Optimizations** 🆕
- **Status**: Using Btrfs for `/var/log` with LUKS encryption
- **Opportunities**:
  - Enable autodefrag for SSD (less relevant, but helps with wear)
  - Monitor compression ratio
  - Consider `noatime` for root mount if not already set

### 6. **I/O Scheduler Tuning** 🆕
- **Status**: Default (likely mq-deadline for NVMe)
- **NVMe SSDs**: Already optimized by default
- **Opportunity**: Monitor latency with `iostat`

### 7. **Ethernet Power Management** 🆕
- **Status**: Found USB network adapter (`enp0s20f0u1u2u4`)
- **Current**: Runtime PM likely already active
- **Opportunity**: Ensure autosuspend is aggressive (0ms delay when not needed)

### 8. **L3 Cache QoS (if available)** 🆕
- **Status**: Arrow Lake doesn't expose Cache QoS to userspace
- **Note**: Not applicable for this hardware

### 9. **Frequency Locking on Battery** 🆕
- **Status**: Current implementation uses EPP + min_perf_pct
- **Alternative**: Could hard-limit max frequency on battery
- **Consideration**: Trade-off between power and responsiveness

### 10. **dGPU VRAM Power Gating** 🆕
- **Status**: NVIDIA allows VRAM power gating in D3cold state
- **Note**: Already happening via runtime PM suspension
- **Verification**: Check nvidia-smi power metrics when suspended

### 11. **KDE Compositor GPU Isolation** 🆕 (IMPLEMENT)
- **Goal**: Force KDE to use only iGPU on battery
- **Implementation**: 
  - Create env vars: `__GLX_VENDOR_LIBRARY_NAME=mesa` + `DRI_PRIME=0`
  - Set in KDE startup scripts
  - Only apply on battery mode
  - **File**: `~/.config/plasma-workspace/env/gpu-battery.sh`

### 12. **Fan/Thermal Control** 🆕
- **Status**: Likely controlled by firmware
- **Tools**: asusctl for ROG laptops
- **Current**: Using platform profile (quiet/balanced/performance)
- **Opportunity**: Monitor with `sensors` command

### 13. **Bluetooth Antenna Power** 🆕
- **Status**: Currently off on battery via network.sh ✅
- **Verified**: Working

### 14. **Display Brightness Dimming** 🆕
- **Status**: Manual currently
- **Opportunity**: Auto-dim on battery (via GNOME/KDE settings already available)
- **Current**: Manual control sufficient for testing

### 15. **Memory Pressure Stall Info (PSI)** 🆕
- **Status**: Enabled on modern kernels
- **Monitoring**: `/proc/pressure/*`
- **Useful for**: Detecting swap thrashing
- **Action**: If high PSI, reduce zram or increase available RAM

## Priority for Implementation

### High Priority (Significant Impact)
1. ✅ **KDE Compositor GPU Isolation** - Prevents dGPU wake (10-15W savings)
2. ✅ **Intel GPU Frequency Scaling** - Reduces iGPU power draw (2-3W savings)
3. ⚠️ **Reduce Swappiness** - Prevent unnecessary I/O (1-2W potential)

### Medium Priority (Noticeable Impact)
4. 🔄 **PSR Monitoring** - Already likely enabled, verify if beneficial
5. 🔄 **Scheduler Fine-tuning** - Already good, marginal gains
6. 🔄 **Ethernet Power Management** - Verify aggressive autosuspend

### Low Priority (Marginal/Situational)
7. 🔄 **Btrfs Optimizations** - Mostly disk wear reduction
8. 🔄 **I/O Scheduler Tuning** - Already optimized for NVMe
9. 🔄 **Display Auto-dimming** - Requires user testing
10. 🔄 **Fan Control** - Thermal-limited, not power-limited

## Recommendations

1. **Implement KDE Compositor GPU Isolation First** - Highest impact
2. **Add Intel GPU Frequency Scaling Module** - Easy, meaningful savings
3. **Monitor PSI and Swap** - Understand actual memory pressure
4. **Profile Power Draw** - Before/after measurements with `nvidia-smi`, kernel logs
5. **Test on Real Battery** - Validate actual battery life improvements

## Estimated Power Savings

- **KDE Compositor Isolation**: -10 to -15W (prevent unnecessary dGPU wake)
- **Intel GPU Frequency Scaling**: -2 to -3W (reduce iGPU clock on battery)
- **Reduce Swappiness**: -1 to -2W (prevent thrashing I/O)
- **Combined Target**: 13-20W power reduction on battery

## Current Known Issues

1. ✅ PCIe ASPM is read-only (kernel cmdline controlled) - Not critical
2. ✅ supergfxctl is abandoned - Using asusctl + runtime PM instead
3. ⚠️ dGPU still wakes when KDE compositor uses it - **SOLVE WITH GPU ISOLATION**

---

**Last Updated**: 2026-03-18
**Hardware**: ASUS ROG Zephyrus G16 (GU605CX)
**OS**: CachyOS with KDE Plasma
