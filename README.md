# ZephyrusOptimizations

Linux optimizations for ASUS ROG Zephyrus G16 (GU605CX) on CachyOS with multi-DE support (GNOME, KDE Plasma).

## Hardware

| Component | Specification |
|-----------|---------------|
| Model | ASUS ROG Zephyrus G16 (GU605CX) |
| CPU | Intel Core Ultra 9 285H (Arrow Lake) - 6 P-cores, 8 E-cores, 2 LP E-cores |
| iGPU | Intel Arc Graphics (Xe LPG) |
| dGPU | NVIDIA RTX 5090 |
| Display | 2560x1600 OLED 240Hz (VRR 48-240Hz) |
| IR Camera | Shinetech USB2.0 (Windows Hello compatible) |

## Prerequisites

### Required Packages

```bash
# CachyOS / Arch
sudo pacman -S asusctl supergfxctl power-profiles-daemon

# AUR packages
yay -S howdy   # For IR face authentication
```

### Services

```bash
# Enable ASUS daemon
sudo systemctl enable --now asusd

# Enable power profiles
sudo systemctl enable --now power-profiles-daemon

# Enable supergfxd (GPU switching)
sudo systemctl enable --now supergfxd
```

## Project Structure

```
├── core/                  # DE-agnostic modules (CPU, GPU, network, audio, etc.)
├── de/
│   ├── gnome/            # GNOME-specific (display via Mutter, extensions)
│   └── kde/              # KDE-specific (display via kscreen-doctor, effects)
├── modules/              # Legacy location (being phased out)
├── power-switch.sh       # Original GNOME-only script (legacy)
└── power-switch-unified.sh  # New multi-DE script (recommended)
```

### Desktop Environment Support

**Supported DEs:**
- ✅ GNOME (Wayland/X11) - Mutter D-Bus, gnome-extensions
- ✅ KDE Plasma (Wayland/X11) - kscreen-doctor, kwin effects

**Auto-detection:** The unified script automatically detects your DE and loads appropriate modules.

## Features

### Power Management (`power-switch-unified.sh`)

Automatic power profile switching between AC and battery:

| Mode | Actual Draw | Features |
|------|-------------|----------|
| Battery | ~10-12W idle | Turbo off, EPP=power, 48-60Hz VRR, WiFi power-save, dGPU suspended |
| AC | Full 240W | All cores boosted, EPP=performance, 240Hz display, max cooling |

> **Note**: The original 3-5W target was unrealistic. RAPL power capping caused system lag without meaningful power savings on Arrow Lake (Intel Thread Director + deep C-states are already efficient). Current approach: let the CPU idle naturally, focus on peripherals and display.

```bash
# Manual switching (unified multi-DE script)
sudo ./power-switch-unified.sh battery
sudo ./power-switch-unified.sh ac
sudo ./power-switch-unified.sh status

# Dry-run mode (preview changes)
sudo ./power-switch-unified.sh battery --dry-run

# Legacy GNOME-only script (still available)
sudo ./power-switch.sh battery
sudo ./power-switch.sh ac

# Auto-switching via udev (see UDEV_SETUP.md for installation)
# Once installed, power switches automatically when AC plugged/unplugged
```

### IR Face Authentication (`modules/ir-auth-setup.sh`)

Windows Hello-style face recognition for login and sudo using the built-in IR camera.

```bash
# Configure howdy for Zephyrus G16
sudo ./modules/ir-auth-setup.sh configure

# Setup PAM for sudo and GDM login
sudo ./modules/ir-auth-setup.sh pam

# Add your face
sudo ./modules/ir-auth-setup.sh add

# Test
sudo howdy test
```

**Configuration highlights:**
- IR camera: `/dev/video2` (640x400 @ 15fps greyscale)
- HOG detection (battery-friendly, CNN disabled)
- Certainty: 4.5 (adjust 3.0-5.0 based on experience)
- Failed auth snapshots saved to `/var/log/howdy/snapshots`

### Display Management

**GNOME** (`de/gnome/display.sh`, `de/gnome/set-refresh-rate.py`):
- Uses Mutter D-Bus API for refresh rate control
- Automatic switching (60Hz battery / 240Hz AC)
- VRR support (48-60Hz adaptive on battery)

**KDE Plasma** (`de/kde/display.sh`):
- Uses kscreen-doctor for refresh rate control
- Automatic switching (60Hz battery / 240Hz AC)
- VRR support (48-60Hz adaptive on battery)

### Visual Effects Management

**GNOME** (`de/gnome/extensions.sh`):
- Disables heavy extensions on battery (blur-my-shell)
- Re-enables on AC for full visual experience

**KDE Plasma** (`de/kde/effects.sh`):
- Disables compositor effects on battery (blur, transparency)
- Reduces animation speed for power savings
- Re-enables full effects on AC

### Core Modules (DE-agnostic)

All modules in `core/` work on any desktop environment:

| Module | Description |
|--------|-------------|
| `cpu-power.sh` | RAPL limits, EPP, turbo, HWP boost |
| `cpu-cores.sh` | Core management (all online - Thread Director handles efficiency) |
| `gpu.sh` | dGPU power state verification (Hybrid mode) |
| `nvme-power.sh` | NVMe power management (disable unused drives like Windows disk) |
| `audio.sh` | Audio codec power save |
| `network.sh` | WiFi/Bluetooth power management |
| `pci-power.sh` | PCIe ASPM, runtime PM |
| `usb.sh` | USB autosuspend (skips HID) |
| `kernel-tunables.sh` | NMI watchdog, VM writeback |
| `platform.sh` | Platform profile via asusctl |
| `browser-brave.sh` | Browser optimizations |

## Status

- ✅ Sound issues fixed
- ✅ Brightness control fixed
- ✅ Power switching (AC/Battery)
- ✅ IR face authentication (login + sudo)
- ✅ Display VRR (48-60Hz battery, 240Hz AC)
- ✅ dGPU power management (suspended in Hybrid mode)

## Known Issues

### supergfxctl GPU Switching

`supergfxctl -m Integrated` works when run manually but requires logout. The dGPU in Hybrid mode already idles at near-zero power when suspended, so Integrated mode provides minimal additional savings.

**Workaround**: Keep GPU in Hybrid mode - RTX 5090 suspends automatically when unused.

See [PLAN.md](PLAN.md) for details.

## Migration Notes

The project has been reorganized for multi-DE support:

**Old structure** (GNOME-only):
```
modules/display.sh          # GNOME Mutter D-Bus
modules/cpu-power.sh        # Mixed with display code
power-switch.sh             # Monolithic GNOME script
```

**New structure** (Multi-DE):
```
core/cpu-power.sh           # DE-agnostic
de/gnome/display.sh         # GNOME-specific
de/kde/display.sh           # KDE-specific
power-switch-unified.sh     # Auto-detects DE
```

**Recommendation:** Use `power-switch-unified.sh` going forward. The old `power-switch.sh` is kept for backward compatibility.

## Testing Your Setup

```bash
# Check which DE is detected
./power-switch-unified.sh status

# Test battery mode (dry-run first)
sudo ./power-switch-unified.sh battery --dry-run
sudo ./power-switch-unified.sh battery

# Test AC mode
sudo ./power-switch-unified.sh ac --dry-run
sudo ./power-switch-unified.sh ac

# Test individual modules
cd core
./cpu-power.sh status
./gpu.sh status

# Test DE-specific modules
cd de/gnome  # or de/kde
./display.sh status
```

## Documentation

- [PLAN.md](PLAN.md) - Detailed optimization plan and technical notes
- [DISPLAY-INFO.md](DISPLAY-INFO.md) - Display configuration details
- [REORGANIZATION_PLAN.md](REORGANIZATION_PLAN.md) - Multi-DE architecture
- [UDEV_SETUP.md](UDEV_SETUP.md) - **Automatic power switching via udev rules**
- [POWER_ANALYSIS.md](POWER_ANALYSIS.md) - CPU power consumption analysis
- [GPU_ISOLATION_ANALYSIS.md](GPU_ISOLATION_ANALYSIS.md) - GPU power optimization details
- [docs/GPU_POWER_SWITCH.md](docs/GPU_POWER_SWITCH.md) - **dGPU power switch (eco/standard), GSP firmware limitation, and future fix**
- [CHROMIUM_IGPU_SOLUTION.md](CHROMIUM_IGPU_SOLUTION.md) - Forcing Chromium apps to use iGPU

## License

MIT
