# ASUS ROG Fan Curve Troubleshooting

## Current State

**Symptom**: Fans spin at ~2100 RPM at 46°C despite custom fan curve configured to keep them near-off below 70°C.

**Hardware**: ASUS laptop with Intel Core Ultra 9 285H + RTX 5090
**Kernel**: 7.0.10-1-cachyos (also tested: 7.1.0-rc4-1-cachyos-rc - same issue)
**Drivers**: `asus_wmi`, `asus_armoury` (identical config in both kernels)

## Root Cause

The fan curve is correctly written to the `asus_custom_fan_curve` hwmon (hwmon7):
- `pwm1_enable=1` (manual curve defined ✓)
- All 8 temp/pwm points match config

But the actual fan controller (`asus` hwmon6) stays in:
- `pwm1_enable=2` (EC automatic mode ✗ — ignores custom curve)

The kernel driver writes curve values to the EC via ACPI methods, but **the EC does not switch to manual (FANM=4) mode**. On some ASUS models, the DEFC ACPI method needs to be called to set FANM=4 before the EC accepts custom curves. This is likely not happening for this specific laptop model.

## What Was Tried

| Attempt | Result |
|---------|--------|
| Config in `/etc/asusd/fan_curves.ron` | ✓ asusd loads and parses it |
| asusd writes to hwmon7 via sysfs | ✓ values stored in `asus_custom_fan_curve` |
| Switching platform profile triggers re-apply | ✓ asusd writes curve for active profile |
| `systemctl restart asusd` | No change — EC stays in auto |
| `linux-cachyos-rc` (7.1.0-rc4) | Identical ASUS config — no difference |

## Possible Solutions (to research)

### 1. Force pwm1_enable=1 on hwmon6
```bash
# This would tell the kernel to take manual fan control
# But the file is root-owned and may reject the write
echo 1 | sudo tee /sys/class/hwmon/hwmon6/pwm1_enable
# If it returns "Invalid argument", the hardware/firmware doesn't support manual override
```

### 2. Call ACPI DEFC method manually
Install `acpi_call` and try to invoke the DEVC (Define Custom Fan Curve) ACPI method directly:
```bash
sudo pacman -S acpi_call-dkms
sudo modprobe acpi_call
# Discover available methods:
sudo cat /proc/acpi/call
# Call the fan curve enable method (model-specific):
# echo '\_SB.PCI0.LPC0.EC0.DEFC' | sudo tee /proc/acpi/call
```

### 3. Report to asusctl upstream
File an issue at https://gitlab.com/asus-linux/asusctl with:
- Laptop model
- Kernel version
- Output of `cat /sys/class/hwmon/hwmon6/pwm1_enable`
- Output of `journalctl -b -u asusd | grep -i "fan"`
- To help add model-specific quirk support

### 4. Check firmware/BIOS update
Check if ASUS has released a BIOS update for this laptop model. The fan curve ACPI methods (SPLX, DEFC) may need firmware fixes.

### 5. Alternative: manual hwmon override
Some ASUS models support writing PWM values directly:
```bash
# Check if hwmon6 has writable pwm1
cat /sys/class/hwmon/hwmon6/pwm1
# If writable, can manually set fan speed
# But this is all-or-nothing, not a curve
```
