# Zephyrus G16 Automatic Power Management Setup

This document describes how to set up automatic power switching when AC adapter is plugged/unplugged.

## ⚠️ Important: Boot Behavior

**If you boot on battery, optimizations won't apply until first AC plug/unplug event.**

To enable automatic optimization on boot, you need the **boot-time systemd service** (see installation below).

## Components

1. **power-switch-unified.sh** - Main power management script (already present)
2. **zephyrus-power-event.sh** - Udev event handler (triggers power switching)
3. **99-zephyrus-power.rules** - Udev rule (detects AC plug/unplug)
4. **zephyrus-power-boot.service** - Systemd service (applies optimizations on boot) - OPTIONAL BUT RECOMMENDED

## Installation

### Quick Installation (Recommended)

This handles everything including boot-time optimization:

```bash
sudo ./install-udev-autoswitching.sh
```

It will ask if you want to install boot-time service. **Answer YES** to ensure battery optimizations apply immediately on boot.

### Manual Installation

If you prefer to install manually:

#### Step 1: Install the udev event handler
# Copy event handler to system path
sudo cp zephyrus-power-event.sh /usr/local/bin/zephyrus-power-event
sudo chmod +x /usr/local/bin/zephyrus-power-event

# Create log file
sudo touch /var/log/zephyrus-power.log
sudo chmod 644 /var/log/zephyrus-power.log
```

### Step 2: Install the udev rule

```bash
# Copy udev rule
sudo cp 99-zephyrus-power.rules /etc/udev/rules.d/

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Step 3: Test the setup

#### Test AC mode manually:
```bash
# Simulate AC connected event
sudo /usr/local/bin/zephyrus-power-event 1

# Check log
tail /var/log/zephyrus-power.log
```

#### Test battery mode manually:
```bash
# Simulate battery event
sudo /usr/local/bin/zephyrus-power-event 0

# Check log
tail /var/log/zephyrus-power.log
```

#### Test with actual AC plug/unplug:
```bash
# Monitor udev events
sudo udevadm monitor --environment --udev | grep -i "power_supply"

# In another terminal, watch the log
tail -f /var/log/zephyrus-power.log

# Now plug/unplug your AC adapter
# You should see events and power switching happening automatically
```

## How It Works

1. **Udev detects AC change** - When you plug/unplug AC adapter:
   - Udev receives event from `ACAD` (AC adapter device)
   - Checks `POWER_SUPPLY_ONLINE` attribute (1=AC, 0=battery)

2. **Event handler is triggered** - `/usr/local/bin/zephyrus-power-event` runs with AC status:
   - Logs the event to `/var/log/zephyrus-power.log`
   - Calls `power-switch-unified.sh` with appropriate mode

3. **Power optimizations applied** - `power-switch-unified.sh` executes:
   - Battery mode: CPU EPP=power, turbo off, 60Hz display, disable Windows NVMe, etc.
   - AC mode: CPU EPP=performance, turbo on, 240Hz display, re-enable Windows NVMe, etc.

## Monitoring

### View automatic switching log:
```bash
tail -f /var/log/zephyrus-power.log
```

### Check current power state:
```bash
./power-switch-unified.sh status
```

### Check if AC is connected:
```bash
cat /sys/class/power_supply/ACAD/online
# 1 = AC connected
# 0 = on battery
```

## Troubleshooting

### Udev rule not triggering:

1. Check udev is monitoring the right device:
```bash
udevadm info --attribute-walk --name=/sys/class/power_supply/ACAD
```

2. Test udev rule manually:
```bash
sudo udevadm test /sys/class/power_supply/ACAD
```

3. Check udev logs:
```bash
journalctl -f -u systemd-udevd
```

### Power switching not working:

1. Test script manually:
```bash
sudo /usr/local/bin/zephyrus-power-event 1  # AC
sudo /usr/local/bin/zephyrus-power-event 0  # Battery
```

2. Check script permissions:
```bash
ls -l /usr/local/bin/zephyrus-power-event
# Should be: -rwxr-xr-x (executable)
```

3. Check log for errors:
```bash
tail -50 /var/log/zephyrus-power.log
```

## Uninstallation

To disable automatic power switching:

```bash
# Remove udev rule
sudo rm /etc/udev/rules.d/99-zephyrus-power.rules
sudo udevadm control --reload-rules

# Remove event handler (optional)
sudo rm /usr/local/bin/zephyrus-power-event

# Remove log file (optional)
sudo rm /var/log/zephyrus-power.log

# If boot service was installed
sudo systemctl disable zephyrus-power-boot.service
sudo rm /etc/systemd/system/zephyrus-power-boot.service
sudo systemctl daemon-reload
```

## Notes

- **With boot service**: Optimizations apply immediately on boot (battery or AC)
- **Without boot service**: Optimizations apply on first AC plug/unplug event
- **Manual override**: You can always run `sudo ./power-switch-unified.sh battery` or `ac` manually to override.
- **Log rotation**: Consider adding `/var/log/zephyrus-power.log` to logrotate if it grows large.
- **KDE compositor GPU isolation**: Requires logout/login to take effect (only affects the GPU env variables).

## Boot Service Details

The boot service (if installed) does the following:

1. **On boot**: Checks current AC status via `/sys/class/power_supply/ACAD/online`
2. **If on battery** (AC=0): Runs `zephyrus-power-event 0` → applies battery optimizations
3. **If plugged in** (AC=1): Runs `zephyrus-power-event 1` → applies AC optimizations
4. Logs result to `/var/log/zephyrus-power.log`

### To verify boot service is working:

```bash
# Check service is enabled
systemctl is-enabled zephyrus-power-boot.service
# Output: enabled

# Check last run
journalctl -u zephyrus-power-boot.service -n 20

# Check if optimizations were applied
tail /var/log/zephyrus-power.log
```

### To manually manage boot service:

```bash
# View service
sudo systemctl status zephyrus-power-boot.service

# Disable boot service (keep udev plug/unplug events)
sudo systemctl disable zephyrus-power-boot.service

# Re-enable
sudo systemctl enable zephyrus-power-boot.service

# Test manually (simulate boot)
sudo /usr/local/bin/zephyrus-power-event $(cat /sys/class/power_supply/ACAD/online)
```

## Example Workflow

### First time setup:

```bash
# 1. Install everything (quick method)
cd ~/Code/ZephyrusOptimizations
sudo ./install-udev-autoswitching.sh
# Say YES to boot service

# 2. Reboot to test
sudo reboot

# 3. Check if optimizations applied
./power-switch-unified.sh status
tail /var/log/zephyrus-power.log

# 4. Test plug/unplug
# Unplug AC → should see battery optimizations in log
# Plug AC → should see AC optimizations in log
```

### What happens at boot on battery:

```
[System boots on battery]
  ↓
[systemd loads zephyrus-power-boot.service]
  ↓
[Service reads /sys/class/power_supply/ACAD/online → 0]
  ↓
[Runs: /usr/local/bin/zephyrus-power-event 0]
  ↓
[power-switch-unified.sh battery executes]
  ↓
[Battery optimizations applied immediately]
  ✓ Windows NVMe disabled
  ✓ CPU EPP set to power
  ✓ Turbo disabled
  ✓ 60Hz display
  ✓ KDE effects reduced
  ✓ Logged to /var/log/zephyrus-power.log
```
