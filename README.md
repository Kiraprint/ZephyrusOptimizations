# ZephyrusOptimizations

Linux power optimizations for ASUS ROG Zephyrus G16 (GU605CX) on CachyOS, with multi-DE support
(GNOME, KDE Plasma) and explicit handling of a hybrid NVIDIA setup where the dGPU must stay off.

## Hardware

| Component | Specification |
|-----------|---------------|
| Model | ASUS ROG Zephyrus G16 (GU605CX) |
| CPU | Intel Core Ultra 9 285H (Arrow Lake) - 6 P-cores, 8 E-cores, 2 LP E-cores |
| iGPU | Intel Arc Graphics (Arrow Lake) - `xe` KMD, PCI `0000:00:02.0` |
| dGPU | NVIDIA RTX 5090 Mobile - PCI `0000:01:00.0` |
| Display | 2560x1600 OLED 240Hz (VRR 48-240Hz) |
| IR Camera | Shinetech USB2.0 (Windows Hello compatible) |

## Prerequisites

```bash
# CachyOS / Arch
sudo pacman -S asusctl power-profiles-daemon

# AUR packages
yay -S howdy-git      # IR face authentication (see setup/ir-auth-setup.sh)
```

External tools this repo calls but does not ship (installed separately under `/usr/local/bin`):

| Tool | Role |
|------|------|
| `cardwire` / `cardwired` | eBPF-based dGPU **access** blocking in integrated mode (it does not cut power) |
| `dgpu-switch.sh` | ACPI/EC rail control (`eco` = `dgpu_disable=1`, `standard` = `0`) |
| `nvidia-hide` | per-command dGPU hiding wrapper |

```bash
sudo systemctl enable --now asusd
sudo systemctl enable --now power-profiles-daemon
```

## Project Structure

```
├── core/                  # DE-agnostic modules (CPU, GPU, network, audio, …)
├── de/
│   ├── gnome/             # Mutter D-Bus display + shell extensions
│   └── kde/               # kscreen-doctor display, KWin effects/compositor/services
├── docs/                  # current technical notes (NVIDIA D3 investigation, GPU power, KDE)
│   └── archive/           # superseded session notes / research dumps (historical only)
├── setup/                 # one-off setup helpers (IR/auth via howdy)
├── power-switch-unified.sh    # entry point: auto-detects DE, runs core/ + de/ modules
├── install-udev-autoswitching.sh  # installs udev rules + event handler
├── zephyrus-power-event.sh    # udev AC/battery event handler
├── zephyrus-power-boot.service, zephyrus-scx-lavd.service
├── nvidia-powerd-guard.sh, nvidia-powerd-guard.conf   # safe nvidia-powerd restarts
├── dgpu-cleanup.sh, 90-dgpu-cleanup.rules             # kernel-remove uevent cleanup path
├── 99-zephyrus-power.rules, aspm-boot-params.conf
└── test-structure.sh      # verifies core/ + de/ layout
```

## Features

### Power Management (`power-switch-unified.sh`)

```bash
sudo ./power-switch-unified.sh battery        # also: ac | status
sudo ./power-switch-unified.sh battery --dry-run
```

| Mode | CPU | Display | dGPU |
|------|-----|---------|------|
| Battery | turbo off, `min_perf_pct=8`, EPP `power` | 60Hz, VRR 48-60 | cardwire integrated + EC rail cut (`dgpu-switch eco`), NVIDIA modules unloaded, suspend services off |
| AC | turbo on, `min_perf_pct=15`, `max_perf_pct=100`, EPP `balance_performance` | 240Hz | `dgpu-switch standard` + cardwire hybrid, modules/services restored |

Platform profile (`quiet`/`low-power` → `performance`) is only overridden on AC; a manual
`balanced`/`performance` choice survives power events.

> **Note**: the original 3–5 W idle target was unrealistic. RAPL power capping caused system lag
> without meaningful savings on Arrow Lake (Thread Director + deep C-states are already efficient),
> so the current approach lets the CPU idle naturally and focuses on display, peripherals and the dGPU.

Auto-switching via udev: see [UDEV_SETUP.md](UDEV_SETUP.md).

### dGPU handling — what actually happens

Two independent layers, often confused:

1. **Access blocking** — `cardwired` installs an eBPF LSM hook that makes the dGPU subtree
   (`0000:01:00.0`, its root port, audio function) invisible to userspace: `open()` returns `ENOENT`,
   `readdir` is rewritten. `lspci`/sysfs look "gone" while the kernel still has the device. No bus
   removal, no driver event, no MUX write.
2. **Power** — only the ASUS EC rail actually cuts the dGPU (`dgpu_disable=1` via `dgpu-switch.sh eco`).
   `NVreg_DynamicPowerManagement=0x00` keeps the device on the bus so the driver never logs a
   zombie against a dead device.

`nvidia-powerd-guard.sh` makes cardwire's `nvidia-powerd` restarts safe while the dGPU is hidden.
Evidence, falsified hypotheses and reproduction steps: [docs/NVIDIA_D3COLD_REINVESTIGATION.md](docs/NVIDIA_D3COLD_REINVESTIGATION.md)
and [docs/NVIDIA_D3_REMOVAL_EVIDENCE.md](docs/NVIDIA_D3_REMOVAL_EVIDENCE.md).

### IR Face Authentication (`setup/ir-auth-setup.sh`)

Windows Hello-style face recognition for login and sudo using the built-in IR camera.

```bash
sudo ./setup/ir-auth-setup.sh configure   # howdy config for this machine
sudo ./setup/ir-auth-setup.sh pam         # PAM for sudo + display manager
sudo ./setup/ir-auth-setup.sh add         # enroll face
sudo howdy test
```

IR camera `/dev/video2` (640x400 @ 15fps greyscale), HOG detection, CNN disabled for battery life,
certainty 4.5. Failed-auth snapshots land in `/var/log/howdy/snapshots`.

### Display / Effects / Services

| DE | Scripts | Behaviour |
|----|---------|-----------|
| GNOME | `de/gnome/display.sh`, `set-refresh-rate.py`, `extensions.sh` | Mutter D-Bus refresh control (60/240Hz), VRR, heavy extension toggling |
| KDE | `de/kde/display.sh`, `effects.sh`, `services.sh`, `compositor-gpu.sh` | kscreen-doctor refresh/VRR, effect toggles, compositor pinned to iGPU |

### Core Modules (DE-agnostic)

| Module | Description |
|--------|-------------|
| `cpu-power.sh` | turbo, EPP, HWP boost, `min_perf_pct` (no RAPL cap by design) |
| `cpu-cores.sh` | core online/offline management (Thread Director handles efficiency) |
| `gpu.sh` | dGPU power: cardwire mode + EC rail (`dgpu-switch eco/standard`), NVIDIA module/service lifecycle |
| `dgpu-monitor.sh` | dGPU state logging for power-switch debugging |
| `igpu-freq.sh` | iGPU frequency scaling (min/max MHz) |
| `nvidia-power-cap.sh` | unlock the RTX 5090 power cap past the EC ceiling |
| `nvme-power.sh` | NVMe power management (unused drives) |
| `audio.sh` | HDA codec power save |
| `network.sh` | WiFi/Bluetooth power management |
| `pci-power.sh` | PCIe ASPM + runtime PM |
| `usb.sh` | USB autosuspend (HID-aware) |
| `kernel-tunables.sh` | NMI watchdog, VM writeback |
| `platform.sh` | ACPI platform profile |
| `browser-brave.sh` | Brave GPU/rendering flags |
| `chromium-igpu.sh` | force Chromium/Electron apps onto the iGPU (flag files) |

## Status

- ✅ Sound, brightness control, display VRR (48–60Hz battery / 240Hz AC)
- ✅ Power switching on AC/battery, automatic via udev
- ✅ IR face authentication (login + sudo)
- ✅ dGPU off on battery (EC rail), available on AC
- ✅ Chromium/Electron apps pinned to the iGPU (Brave, Paseo, Mercurygram verified)

## Known Issues

### `xe` TLB invalidation fence timeouts (Arrow Lake)

```
xe 0000:00:02.0: [drm] *ERROR* TLB invalidation fence timeout, seqno=N recv=N-1
```

Each hit stalls the whole GT for ~1 s — every GPU client (compositor included) freezes briefly, which
shows up as stutter during interaction. Root cause: on the standalone media GT the CPU reads a stale
cache line of the G2H CTB; `i915` works it around as `Wa_22016122933`, `xe` did not inherit it.
Media/VA-API workloads are the main trigger.

Tracked upstream (3-patch series, A/B-tested on `7d51`/`7dd1`): [CachyOS/linux-cachyos#1036](https://github.com/CachyOS/linux-cachyos/issues/1036),
[GitLab xe#8678](https://gitlab.freedesktop.org/drm/xe/kernel/-/work_items/8678).
Verify with `journalctl -k -b | grep -c 'TLB invalidation fence timeout'`.

### dGPU mode switching

`supergfxctl`-style integrated switching is replaced by cardwire + the EC rail. Cutting the rail on
battery means the dGPU needs `standard` (or a reboot) to come back; while it is rail-off, cardwire
still reports `hybrid` — harmless, there is nothing to route until it re-enumerates.

## Testing

```bash
./test-structure.sh                      # core/ + de/ layout
./power-switch-unified.sh status         # DE detection + current state
sudo ./power-switch-unified.sh battery --dry-run
cd core && ./gpu.sh status               # per-module status/dry-run
```

## Documentation

- [docs/NVIDIA_D3COLD_REINVESTIGATION.md](docs/NVIDIA_D3COLD_REINVESTIGATION.md) — dGPU "removal" explained (eBPF hiding vs EC rail)
- [docs/NVIDIA_D3_REMOVAL_EVIDENCE.md](docs/NVIDIA_D3_REMOVAL_EVIDENCE.md) — logs, kprobes, strace evidence
- [docs/GPU_POWER_SWITCH.md](docs/GPU_POWER_SWITCH.md) — eco/standard, GSP firmware limitation
- [docs/WHY_NO_RAPL.md](docs/WHY_NO_RAPL.md) — why there is no RAPL cap
- [UDEV_SETUP.md](UDEV_SETUP.md) — automatic switching via udev
- [DISPLAY-INFO.md](DISPLAY-INFO.md) — panel/VRR details
- [GPU_ISOLATION_ANALYSIS.md](GPU_ISOLATION_ANALYSIS.md), [CHROMIUM_IGPU_SOLUTION.md](CHROMIUM_IGPU_SOLUTION.md) — keeping Chromium/Electron on the iGPU
- [MUX_SWITCH_BATTERY_MODE.md](MUX_SWITCH_BATTERY_MODE.md), [WHY_LINUX_CANT_DO_SEAMLESS_GPU_SWITCHING.md](WHY_LINUX_CANT_DO_SEAMLESS_GPU_SWITCHING.md)
- [ZRAM_PARAMETERS_GUIDE.md](ZRAM_PARAMETERS_GUIDE.md), [ASUS_FAN_CURVE_TROUBLESHOOTING.md](ASUS_FAN_CURVE_TROUBLESHOOTING.md)
- [docs/archive/](docs/archive/) — superseded session notes (Mar–Apr 2026) kept for history only

## License

MIT
