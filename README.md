# ZephyrusOptimizations

Linux optimizations for ASUS ROG Zephyrus G16 (GU605CX) on CachyOS + GNOME.

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

## Features

### Power Management (`power-switch.sh`)

Automatic power profile switching between AC and battery:

| Mode | Target | Features |
|------|--------|----------|
| Battery | ~3-5W idle | RAPL limits, turbo off, EPP=power, 60Hz display, WiFi power-save |
| AC | Full 240W | All cores boosted, EPP=performance, 240Hz display, max cooling |

```bash
# Manual switching
sudo ./power-switch.sh battery
sudo ./power-switch.sh ac

# Auto-switching via udev (see PLAN.md)
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

### Display Management (`modules/display.sh`, `modules/set-refresh-rate.py`)

- Automatic refresh rate switching (60Hz battery / 240Hz AC)
- VRR support (48-60Hz adaptive on battery)

### Power Modules

| Module | Description |
|--------|-------------|
| `cpu-power.sh` | RAPL limits, EPP, turbo, HWP boost |
| `cpu-cores.sh` | Core management (all online - Thread Director handles efficiency) |
| `gpu.sh` | dGPU power state verification (Hybrid mode) |
| `audio.sh` | Audio codec power save |
| `network.sh` | WiFi/Bluetooth power management |
| `pci-power.sh` | PCIe ASPM, runtime PM |
| `usb.sh` | USB autosuspend (skips HID) |
| `kernel-tunables.sh` | NMI watchdog, VM writeback |
| `platform.sh` | Platform profile via asusctl |

## Status

- ✅ Sound issues fixed
- ✅ Brightness control fixed
- ✅ Power switching (AC/Battery)
- ✅ IR face authentication (login + sudo)
- ⚠️ supergfxctl Integrated mode broken (kernel 6.19 + asus-armoury driver path mismatch)

## Known Issues

### supergfxctl Integrated Mode

`supergfxctl -m Integrated` fails on kernel 6.19 due to driver path changes. **Workaround**: Keep GPU in Hybrid mode - RTX 5090 idles at near-zero power when unused.

See [PLAN.md](PLAN.md) for details.

## Documentation

- [PLAN.md](PLAN.md) - Detailed optimization plan and technical notes
- [DISPLAY-INFO.md](DISPLAY-INFO.md) - Display configuration details
- [modules/README.md](modules/README.md) - Module documentation

## License

MIT
