# Quick Reference - Red Team Fixes

## TL;DR

✅ **Fixed 3 critical bugs in original research document**  
✅ **Safe implementation ready to use**  
✅ **Backup/rollback built-in**

---

## What Changed

### Original Script (BROKEN)
```bash
# ❌ Wrong: Creates ignored modprobe file
echo "options intel_pstate min_perf_pct=15" > /etc/modprobe.d/intel-pstate-optimize.conf

# ❌ Dangerous: Removes keyboard/mouse drivers
sudo modprobe -r usbhid && sudo modprobe usbhid
```

### Fixed Script (SAFE)
```bash
# ✅ Correct: ZRAM optimization (only change needed)
vm.watermark_scale_factor = 125  # Was: 10

# ✅ Intel P-State already correct in core/cpu-power.sh
# Uses sysfs (correct method), not modprobe (wrong method)
```

---

## Usage

### Apply Optimizations
```bash
sudo ./apply-research-optimizations.sh
```

### Rollback
```bash
sudo ./apply-research-optimizations.sh --rollback
```

### Verify
```bash
sysctl vm.watermark_scale_factor  # Should show: 125
```

---

## What Gets Applied

| Setting | Current | New | Effect | Risk |
|---------|---------|-----|--------|------|
| vm.watermark_scale_factor | 10 | 125 | Smoother memory reclaim | None |
| vm.watermark_boost_factor | 0 | 0 | No change (already optimal) | N/A |
| vm.page-cluster | 0 | 0 | No change (already optimal) | N/A |

**Only 1 parameter changes.** Everything else already optimal.

---

## What Does NOT Get Applied (Intentionally)

❌ Intel P-State modprobe (wrong method - ignored by kernel)  
❌ USB HID reload (dangerous - removes keyboard/mouse)  
❌ KDE environment variables (unverified - may not exist)

---

## Critical Bugs Fixed

### Bug #1: Intel P-State
- **Original:** Creates `/etc/modprobe.d/intel-pstate-optimize.conf`
- **Problem:** File is silently ignored (wrong method)
- **Fix:** Removed (already correct in `core/cpu-power.sh`)
- **Source:** https://kernel.org/doc/html/latest/admin-guide/pm/intel_pstate.html

### Bug #2: USB HID Reload
- **Original:** `modprobe -r usbhid && modprobe usbhid`
- **Problem:** Removes keyboard/mouse drivers → system lockup
- **Fix:** Removed entirely (too risky)
- **Source:** `modinfo usbhid` + kernel docs

### Bug #3: KDE Variables
- **Original:** `export KWIN_FRAMERATE_LIMIT=0` (and others)
- **Problem:** Variables don't exist in KWin Plasma 6
- **Fix:** Excluded from implementation (unverified)
- **Source:** KWin source code review

---

## Documentation

| File | Purpose |
|------|---------|
| `RED_TEAM_SUMMARY.md` | This file - overview |
| `DEEP_RESEARCH_CORRECTIONS.md` | Detailed bug analysis |
| `ZRAM_PARAMETERS_GUIDE.md` | Technical ZRAM explanation |
| `apply-research-optimizations.sh` | Safe implementation |

---

## Safety Features

✅ **Automatic backups** before changes  
✅ **Instant rollback** (no reboot needed)  
✅ **Verification** output  
✅ **Idempotent** (safe to run multiple times)  
✅ **No dangerous operations** (no module reloads)

---

## Expected Results

### After Applying:
```bash
$ sysctl vm.watermark_scale_factor
vm.watermark_scale_factor = 125

$ sudo ./power-switch-unified.sh battery
$ cat /sys/devices/system/cpu/intel_pstate/min_perf_pct
8

$ sudo ./power-switch-unified.sh ac
$ cat /sys/devices/system/cpu/intel_pstate/min_perf_pct
30
```

### Benefits:
- Smoother memory management during high RAM usage
- Better browser tab switching responsiveness
- Reduced memory thrashing
- No regressions (all changes reversible)

---

## If Something Goes Wrong

### Instant Rollback:
```bash
sudo ./apply-research-optimizations.sh --rollback
```

### Manual Revert:
```bash
sudo sysctl -w vm.watermark_scale_factor=10
```

### Check Backup:
```bash
ls -la /etc/zephyrus-optimization-backups/
```

---

## Questions?

**Q: Is this safe to apply?**  
A: Yes. Only modifies 1 sysctl parameter, with backup/rollback.

**Q: What if my system becomes unstable?**  
A: Instant rollback: `sudo ./apply-research-optimizations.sh --rollback`

**Q: Do I need to reboot?**  
A: No. Changes take effect immediately.

**Q: What about Intel P-State?**  
A: Already correctly configured in `core/cpu-power.sh` (no action needed).

**Q: Can I run this multiple times?**  
A: Yes. Script is idempotent (safe to re-run).

---

## One-Liner Summary

**Original:** 3 critical bugs (ignored config, dangerous reload, fake variables)  
**Fixed:** Safe ZRAM tuning with backup/rollback, Intel P-State already correct  
**Action:** `sudo ./apply-research-optimizations.sh`
