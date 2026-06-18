# MUX Switch Battery Mode Guide

**Your ASUS ROG Zephyrus G16 (GU605) has hardware MUX switch.**  
This is **more powerful** than software GPU switching.

---

## What is MUX Switch?

MUX (Multiplexer) Switch is a **hardware chip** that can route display output directly to:
- iGPU (Intel Arc) for battery savings
- dGPU (NVIDIA RTX 5090M) for maximum performance
- Both (Hybrid mode)

**Advantage over muxless laptops:**
- ✅ No framerate penalty when using iGPU (direct display routing)
- ✅ External monitors work perfectly on iGPU mode
- ✅ Complete hardware-level GPU power-off (not just D3cold software sleep)
- ✅ ~24W power savings when dGPU disabled

---

## Three GPU Modes (via Firmware)

### 1. **Eco Mode** (iGPU Only - Maximum Battery Life)

```bash
# Enable Eco mode
sudo asusctl armoury set dgpu_disable 1
sudo reboot

# After reboot, verify:
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
# Should show: device not found (dGPU fully powered off)

# Check GPU in use:
glxinfo | grep "OpenGL renderer"
# Should show: Intel Arc Graphics
```

**Power consumption:**
- Desktop idle: ~10-12W (just CPU + iGPU)
- Battery life: **7-9 hours** on 90Wh battery

**Use cases:**
- Long flights, travel
- Office work, web browsing, documents
- When no gaming/ML needed

### 2. **Hybrid Mode** (Auto-Switching - Default)

```bash
# Enable Hybrid mode
sudo asusctl armoury set dgpu_disable 0
sudo reboot

# After reboot, verify:
asusctl armoury get dgpu_disable
# Should show: dgpu_disable = 0
```

**Power consumption:**
- Desktop idle: ~15-20W (dGPU runtime-suspended)
- Gaming: ~120-150W (dGPU active)
- Battery life: **4-6 hours** mixed usage

**Use cases:**
- Gaming on battery (dGPU wakes when needed)
- ML tasks with quick context switching
- Default daily driver mode

### 3. **Ultimate Mode** (dGPU Only - Maximum Performance)

**Note:** Cannot be set via `asusctl` - requires BIOS or Armoury Crate (Windows).

**Use cases:**
- Benchmarking
- Competitive gaming (minimum latency)
- When battery life doesn't matter

---

## Quick Switch Script (Battery-Aware)

Add to your project as `de/kde/mux-switch-battery.sh`:

```bash
#!/usr/bin/env bash
# MUX Switch battery-aware mode

BATTERY_STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)

if [[ "$BATTERY_STATUS" == "Discharging" ]]; then
    echo "Battery detected - switching to Eco mode (iGPU only)"
    sudo asusctl armoury set dgpu_disable 1
    echo "Reboot required to apply changes"
    echo "Run: sudo reboot"
else
    echo "AC detected - switching to Hybrid mode"
    sudo asusctl armoury set dgpu_disable 0
    echo "Reboot required to apply changes"
    echo "Run: sudo reboot"
fi
```

---

## Compare: MUX Switch vs Environment Variables

| Feature | MUX Switch (Firmware) | Environment Variables (Software) |
|---------|---|---|
| **Power savings** | ✅ Complete (dGPU powered off) | ⚠️ Partial (D3cold sleep, ~1W) |
| **Framerate penalty** | ❌ None (direct routing) | ❌ None on laptop screen, ⚠️ Possible on external |
| **Switching time** | ⏱️ Reboot required | ⏱️ Logout required |
| **Reliability** | ✅ Hardware-level (100%) | ⚠️ Software-level (KDE services can wake dGPU) |
| **Works across DEs** | ✅ GNOME, KDE, Hyprland, all | ✅ Most (compositor-specific) |
| **Per-app override** | ❌ No (system-wide) | ✅ Via switcheroo-control |

**Recommendation:**
- Use **MUX Switch** for daily battery/AC switching (maximum power savings)
- Use **Environment Variables** (`compositor-gpu.sh`) when you want to switch within session without rebooting
- Use **switcheroo-control** for per-app dGPU needs (gaming a single game without switching mode)

---

## Integration with Your Project

### Update `power-switch-unified.sh`

Add MUX switch option at the top:

```bash
# Check if MUX switch available
if command -v asusctl &>/dev/null; then
    echo "MUX Switch detected (ASUS ROG)"
    echo "  Eco mode:    sudo asusctl armoury set dgpu_disable 1 && sudo reboot"
    echo "  Hybrid mode: sudo asusctl armoury set dgpu_disable 0 && sudo reboot"
    echo ""
    echo "Or continue with software GPU switching (no reboot, logout required):"
fi
```

### Verify MUX Status

```bash
# Current MUX mode
asusctl armoury get dgpu_disable
# 0 = Hybrid (both GPUs)
# 1 = Eco (iGPU only)

# dGPU PCI device status
lspci | grep -i nvidia
# Present = Hybrid mode
# Not found = Eco mode (dGPU powered off)

# Runtime status (Hybrid mode only)
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
# active = dGPU rendering or apps using it
# suspended = D3cold sleep
```

---

## Troubleshooting

### Issue: dGPU not powering off in Eco mode

**Symptom:**
```bash
asusctl armoury get dgpu_disable
# Shows: 1 (Eco mode)

But:
lspci | grep -i nvidia
# Still shows RTX 5090M
```

**Fix:**
Reboot required for firmware changes to take effect:
```bash
sudo reboot
```

### Issue: Can't switch back to Hybrid from Eco

**Symptom:** System hangs or black screen after switching.

**Fix:**
1. Boot to TTY (Ctrl+Alt+F2)
2. Set Hybrid mode:
```bash
sudo asusctl armoury set dgpu_disable 0
sudo reboot
```

### Issue: Want per-game dGPU without rebooting

**Fix:** Stay in Hybrid mode + use `switcheroo-control`:
```bash
# Install
sudo pacman -S switcheroo-control

# Right-click game icon → "Run using Discrete GPU"
# OR command line:
switcherooctl launch -g 1 steam
```

---

## See Also

- `de/kde/compositor-gpu.sh` - Software GPU switching (alternative to MUX)
- `core/gpu.sh` - GPU status checking
- ASUS asusctl documentation: https://gitlab.com/asus-linux/asusctl
- NVIDIA Advanced Optimus: https://nvidia.custhelp.com/app/answers/detail/a_id/5097

---

**Hardware:** ASUS ROG Zephyrus G16 (GU605CX) - MUX Switch + Advanced Optimus  
**Your advantage:** Most gaming laptops DON'T have MUX - you do. Use it.
