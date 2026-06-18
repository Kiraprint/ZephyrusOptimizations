---
title: "DEEP_RESEARCH_OPTIMIZATION_REPORT - CORRECTIONS AND CLARIFICATIONS"
date: 2026-03-18
status: "Red Team Verified"
---

# Critical Corrections to Deep Research Report

This document addresses **critical errors** found in the original DEEP_RESEARCH_OPTIMIZATION_REPORT.md through red team analysis and verification against official kernel documentation.

## ❌ CRITICAL ERROR #1: Intel P-State Configuration

### Original (INCORRECT):
**Finding 4, Line 112-115:**
```bash
# /etc/modprobe.d/intel-pstate-optimize.conf
options intel_pstate min_perf_pct=15
```

### Reality:
**Source:** https://www.kernel.org/doc/html/latest/admin-guide/pm/intel_pstate.html

`min_perf_pct` is **NOT a modprobe parameter**. It's a **sysfs attribute** at:
```
/sys/devices/system/cpu/intel_pstate/min_perf_pct
```

### Why This Is Wrong:
1. `intel_pstate` is built into the kernel (not loadable module)
2. This parameter does not exist in modprobe options
3. The file created will be **silently ignored**
4. No effect whatsoever

### Correct Implementation:
**Already implemented correctly in `core/cpu-power.sh`:**
- Line 93: Battery mode sets `min_perf_pct=8%` via sysfs
- Line 114: AC mode sets `min_perf_pct=30%` via sysfs

**No action needed** - power-switch-unified.sh already does this correctly!

---

## ❌ CRITICAL ERROR #2: USB HID Module Reload

### Original (DANGEROUS):
**Finding 7, Lines 181-184:**
```bash
echo 'options usbhid mousepoll=0' | sudo tee -a /etc/modprobe.d/usbhid.conf
sudo modprobe -r usbhid && sudo modprobe usbhid
```

### Problems:

1. **`mousepoll=0` does nothing** - it means "use device default", not "reduce polling"
2. **`modprobe -r usbhid` is DANGEROUS** - removes keyboard/mouse driver
3. If run locally (not SSH): **immediate loss of all input devices**
4. Uses `-a` (append) which duplicates options on repeated runs

### Reality:
**Source:** `modinfo usbhid`
```
parm: mousepoll:Polling interval of mice (uint)
```
- `mousepoll=0` → use device default
- `mousepoll=2` → 2ms polling interval (lower frequency)

### Recommendation:
**DO NOT implement this optimization.** Risk >> benefit.

If you really want to reduce USB polling:
1. Only do it in battery mode
2. Test via sysfs first before making permanent
3. Never reload usbhid while using local keyboard/mouse
4. Use higher values (e.g., `mousepoll=8` for 8ms = 125Hz)

---

## ⚠️ ERROR #3: KDE Wayland Environment Variables

### Original (UNVERIFIED):
**Finding 2, Lines 66-69:**
```bash
export KWIN_FRAMERATE_LIMIT=0
export KWIN_OPENGL_SINGLE_BUFFER=1
export KWIN_X11_DISABLE_VSYNC=1
```

### Problems:
1. `KWIN_FRAMERATE_LIMIT` - no documentation exists
2. `KWIN_OPENGL_SINGLE_BUFFER` - no documentation exists
3. `KWIN_X11_DISABLE_VSYNC` - applies to **X11**, not Wayland

### Status:
**Cannot verify these variables exist in KWin Plasma 6.**

### Recommendation:
**DO NOT implement** until verified from KDE source or official documentation.

---

## ✅ ZRAM Configuration - VERIFIED SAFE

### Original Recommendation:
```
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
```

### Current System Values:
```
vm.watermark_boost_factor = 0   ✓ Already optimal
vm.watermark_scale_factor = 10  ← Only this needs changing
vm.page-cluster = 0             ✓ Already optimal
```

### Safe Change:
Only `vm.watermark_scale_factor` needs adjustment: `10 → 125`

**Why it's safe:**
- Default kernel value: 10
- ZRAM-optimized value: 125
- Effect: Starts memory reclaim earlier = smoother with compressed swap
- Risk: Negligible. Worst case = slightly more CPU for compression

**Source:** ArchWiki ZRAM page (used by Pop!_OS, Fedora, others)

### Attribution Correction:
Original document claims "Pop!_OS's documented research" but:
- ArchWiki doesn't cite Pop!_OS research
- These are general VM tuning parameters
- Multiple distros use them independently

**Corrected:** "ZRAM optimization parameters used by Pop!_OS and other distributions"

---

## ✅ Arrow Lake LP E-Cores - VERIFIED CORRECT

### Original Statement (Line 311-316):
> "Your 285H includes 2 LP E-cores in addition to 8 regular E-cores"

### Red Team Initial Claim:
❌ "Arrow Lake mobile does NOT have LP E-cores"

### Verification:
**Red team was WRONG.** Intel Core Ultra 9 285H (Arrow Lake mobile) specification:
- 6 P-cores (Performance)
- 8 E-cores (Efficiency)
- 2 LP E-cores (Low-Power Efficiency)
- **Total: 16 cores**

**Document is CORRECT.**

---

## 📊 Power Savings Claims - CLARIFICATION

### Original Claims:
- "0.5-1W savings" (ZRAM)
- "0.7W savings" (KDE compositor)
- "1-2W savings" (Intel P-State)

### Reality Check (Document Line 268):
> "Without a power meter, these savings are theoretical. Real-world impact may be 50-80% of calculated values"

### Clarification:
**These are estimates, not measurements.**

Actual savings depend on:
- Workload type
- Hardware configuration
- Thermal conditions
- Background processes

**Recommendation:** Treat power savings as "potential benefits" not "guaranteed results."

---

## Summary of Fixes Applied

### File: `apply-research-optimizations.sh`

**Removed:**
- ❌ Intel P-State modprobe configuration (incorrect implementation)
- ❌ USB HID reload commands (dangerous)

**Added:**
- ✅ Backup mechanism before changes
- ✅ Rollback function (--rollback flag)
- ✅ Only modifies vm.watermark_scale_factor (the one that needs changing)
- ✅ Verification output
- ✅ Safe error handling

**Kept:**
- ✅ ZRAM sysctl configuration (safe, verified)

### File: `core/cpu-power.sh`

**No changes needed** - already implements Intel P-State correctly:
- Battery: `min_perf_pct=8%` via sysfs
- AC: `min_perf_pct=30%` via sysfs

---

## Recommendations Going Forward

### Implement Now (Safe):
1. ✅ ZRAM watermark_scale_factor adjustment
2. ✅ Intel P-State (already done correctly)

### Do NOT Implement (Risky/Unverified):
1. ❌ USB HID mousepoll changes
2. ❌ KDE environment variables (unverified)
3. ❌ USB HID module reload

### Future Research Needed:
1. 🔍 Verify KWin environment variables from source
2. 🔍 Measure actual power savings with USB power meter
3. 🔍 Test keyboard backlight power draw (ROG-specific)

---

## Testing Procedure

After applying fixes:

```bash
# 1. Apply optimizations
sudo ./apply-research-optimizations.sh

# 2. Verify ZRAM change
sysctl vm.watermark_scale_factor
# Should show: vm.watermark_scale_factor = 125

# 3. Verify Intel P-State (battery mode)
sudo ./power-switch-unified.sh battery
cat /sys/devices/system/cpu/intel_pstate/min_perf_pct
# Should show: 8

# 4. Verify Intel P-State (AC mode)
sudo ./power-switch-unified.sh ac
cat /sys/devices/system/cpu/intel_pstate/min_perf_pct
# Should show: 30

# 5. If issues, rollback
sudo ./apply-research-optimizations.sh --rollback
```

---

## References Used for Verification

1. **Intel P-State:** https://www.kernel.org/doc/html/latest/admin-guide/pm/intel_pstate.html
2. **Kernel Module Options:** https://wiki.archlinux.org/title/Kernel_module#Setting_module_options
3. **USB Power Management:** https://www.kernel.org/doc/html/latest/driver-api/usb/power-management.html
4. **ZRAM Configuration:** https://wiki.archlinux.org/title/Zram
5. **USB HID Module:** `modinfo usbhid`

---

**Red Team Analysis Completed:** 2026-03-18
**Status:** Critical errors identified and fixed
**Safety Level:** HIGH (after corrections)
