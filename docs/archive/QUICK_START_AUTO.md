# Quick Start: Automatic Power Management

## TL;DR - One Line Installation

```bash
cd ~/Code/ZephyrusOptimizations && sudo ./install-udev-autoswitching.sh
```

This installs:
- ✅ Udev rule to detect AC plug/unplug
- ✅ Event handler to trigger power switching  
- ✅ Boot-time service to optimize on startup
- ✅ Automatic logging to `/var/log/zephyrus-power.log`

## What It Does

| Event | Action |
|-------|--------|
| **Boot on battery** | Immediately applies battery optimizations |
| **Boot on AC** | Immediately applies AC optimizations |
| **Unplug AC** | Automatically switches to battery mode |
| **Plug AC** | Automatically switches to AC mode |

## What Gets Optimized

### Battery Mode (when unplugged):
- Windows NVMe disk disabled (~0.5-2W saved)
- CPU: EPP=power, turbo off, max 2.9GHz
- Display: 60Hz
- KDE effects: Reduced/disabled
- Chromium apps: Forced to iGPU

### AC Mode (when plugged):
- Windows NVMe disk re-enabled
- CPU: EPP=performance, turbo on, up to 5.4GHz
- Display: 240Hz
- KDE effects: Full visual effects
- Chromium apps: Can use dGPU

## Installation Steps

### 1. Run Installer
```bash
cd ~/Code/ZephyrusOptimizations
sudo ./install-udev-autoswitching.sh
```

**When asked**: `Install boot-time power management? [Y/n]`
- **Answer: Y** (YES) - Optimizes on every boot ⭐ Recommended
- **Answer: n** (NO) - Only optimizes on AC plug/unplug events

### 2. Reboot (Optional but Recommended)
```bash
sudo reboot
```

Check if optimizations applied:
```bash
./power-switch-unified.sh status
tail /var/log/zephyrus-power.log
```

### 3. Test It
```bash
# Unplug AC from laptop
# Watch optimizations happen:
tail -f /var/log/zephyrus-power.log

# Then plug AC back in
# Watch AC mode apply
```

## Verify It's Working

### Check boot service status:
```bash
systemctl is-enabled zephyrus-power-boot.service
# Output: enabled
```

### Check udev rule:
```bash
ls /etc/udev/rules.d/99-zephyrus-power.rules
# Should exist
```

### Check event handler:
```bash
ls -lh /usr/local/bin/zephyrus-power-event
# Should be executable
```

### Monitor in real-time:
```bash
tail -f /var/log/zephyrus-power.log
```

## Manual Control (Override Automatic)

Even with auto-switching, you can manually control:

```bash
# Force battery optimizations
sudo /home/kir/Code/ZephyrusOptimizations/power-switch-unified.sh battery

# Force AC optimizations
sudo /home/kir/Code/ZephyrusOptimizations/power-switch-unified.sh ac

# Check current state
./power-switch-unified.sh status
```

## Battery Life Expectations

After automatic optimization:

| Scenario | Typical Draw |
|----------|-------------|
| Idle (no apps) | 6-8W |
| Web browsing | 8-12W |
| Coding (IDE) | 10-15W |
| Light work | 12-20W |
| With VPN (ThroneCore) | Add +15-20W |

**No background apps**: ~6-8W is normal floor  
**With typical apps**: 12-18W is realistic

## Troubleshooting

### Not switching automatically?

1. Check udev rule loaded:
```bash
sudo udevadm info /sys/class/power_supply/ACAD
```

2. Manually test event handler:
```bash
sudo /usr/local/bin/zephyrus-power-event 0  # Battery
sudo /usr/local/bin/zephyrus-power-event 1  # AC
```

3. Check journal logs:
```bash
journalctl -f -u systemd-udevd
```

### Boot service not running?

```bash
# Check status
sudo systemctl status zephyrus-power-boot.service

# View logs
journalctl -u zephyrus-power-boot.service -n 50
```

### Check power-switch script is working:

```bash
# Test manually
sudo ./power-switch-unified.sh battery --dry-run
# Should show all optimizations that would be applied

sudo ./power-switch-unified.sh battery
# Actually apply them
```

## Uninstall

To remove automatic power management:

```bash
# Remove everything
sudo rm /etc/udev/rules.d/99-zephyrus-power.rules
sudo rm /usr/local/bin/zephyrus-power-event
sudo rm /var/log/zephyrus-power.log
sudo systemctl disable zephyrus-power-boot.service
sudo rm /etc/systemd/system/zephyrus-power-boot.service
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
```

Manual control will still work via:
```bash
sudo ./power-switch-unified.sh battery
sudo ./power-switch-unified.sh ac
```

## Important Notes

- ⚠️ **First boot after install**: Optimizations apply automatically (if boot service installed)
- ⚠️ **KDE GPU isolation**: Requires logout/login to take full effect
- ⚠️ **Windows NVMe**: Disabled on battery, re-enabled on AC (safe - Linux disk never touched)
- 📝 **Logging**: Check `/var/log/zephyrus-power.log` for what's happening

## Documentation

For detailed information, see:
- `UDEV_SETUP.md` - Complete installation and troubleshooting guide
- `POWER_ANALYSIS.md` - CPU wattage research and findings
- `README.md` - Full feature documentation

## Support

Any issues? Check the logs:
```bash
# Power switching events
tail -100 /var/log/zephyrus-power.log

# System-wide
journalctl -u zephyrus-power-boot.service -n 50
journalctl -f -u systemd-udevd

# Direct script output
sudo /home/kir/Code/ZephyrusOptimizations/power-switch-unified.sh status
```
