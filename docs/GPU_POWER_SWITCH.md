# dGPU Power Switch: Eco ↔ Standard

Controls the NVIDIA RTX 5090 dGPU at the ACPI-firmware level on ASUS ROG Zephyrus G16.

## The Tool

`/usr/local/bin/dgpu-switch.sh` — direct sysfs interface, no asusctl/supergfxctl dependency.

```
sudo dgpu-switch.sh eco       # dGPU → 0W (immediate)
sudo dgpu-switch.sh standard  # dGPU → power on (may need reboot)
dgpu-switch.sh status         # Current state
```

### How it works

The kernel exposes an ACPI firmware hook at `/sys/devices/platform/asus-nb-wmi/dgpu_disable`:
- **`1`** → ACPI tells the EC to cut power to the dGPU. PCI device stays visible but enters D3cold. Measured: **0W** on the dGPU rail.
- **`0`** → ACPI tells the EC to restore power. GPU wakes from D3cold, PCI config space is accessible again.

This is **not** NVIDIA's runtime PM (RTD3/GC6). It's the same mechanism `asusctl armoury set dgpu_disable` uses, but we write the sysfs file directly — no daemon, no D-Bus, no reboot required for the eco transition.

### Framework integration

Triggered automatically by the power-switch chain:

```
udev (ACAD event)
  → /usr/local/bin/zephyrus-power-event
    → power-switch-unified.sh {battery,ac}
      → core/gpu.sh {battery,ac}
        → dgpu-switch.sh {eco,standard}
```

Unplug AC → dGPU at 0W, display at 60Hz, CPU power-save.  
Plug AC → dGPU power restored, 240Hz back, CPU performance.

## Known Limitation: dGPU Re-enable Needs Reboot (Blackwell + nvidia-open)

Writing `dgpu_disable=0` restores PCI power, but the NVIDIA driver **cannot re-bind** without a full reboot. This affects **all Blackwell (RTX 5090) GPUs** on the open kernel modules.

### Why

Two compounding bugs:

**1. GSP Firmware Heartbeat Lost on GC6 Exit**  
The GSP (GPU System Processor) is a RISC-V co-processor on the GPU that runs NVIDIA's firmware. When the GPU wakes from D3cold (GC6 exit), the firmware's bootstrap path skips `rminit`, which means the heartbeat register (`NV_PGSP_MAILBOX(0)`) is never re-initialized. The host driver sees heartbeat timeout and refuses to bind.

- Confirmed by NVIDIA devs on `open-gpu-kernel-modules` repo (issue #1064)
- Affects all architectures, not just Blackwell
- The host driver has no API to tell GSP-RM to restart heartbeat

**2. Blackwell VBIOS PCI Reset Bug**  
On top of the heartbeat issue, Blackwell VBIOS has a separate bug where a PCI reset (FLR, SBR, or D3cold→D0 transition) can permanently bork the GPU — registers read `0xffffffff`, PCIe link degrades, and only a hard reboot recovers. This is documented in the NVIDIA nova-core kernel patches:

> *"there is a nasty bug in the Blackwell VBIOS that sometimes borks the GPU upon PCI reset, requiring a reboot"*

Attempts that fail (don't bother trying):
- `modprobe -r nvidia && modprobe nvidia` — GSP state stays corrupted
- `echo 1 > /sys/bus/pci/devices/.../reset` — FLR can brick the card on Blackwell
- `echo 1 > .../remove` + rescan — WPR2 region persists, driver won't re-probe
- `nvidia-smi -r` — FLR, same Blackwell VBIOS risk
- setpci SBR — breaks PCIe link entirely

Only reliable recovery: **full reboot**.

### What the fix looks like

NVIDIA's upcoming **nova-core** (Rust GPU driver) adds a proper GSP cleanup sequence:

1. Send `UNLOADING_GUEST_DRIVER` command to GSP → clean shutdown
2. Run FWSEC-SB firmware → reset GSP falcon to pre-libos state
3. Run Booter Unloader → clear WPR2 region
4. Re-probe driver → fresh GSP bootstrap with healthy heartbeat

These patches are landing in 2026 for nova-core. The current `nvidia-open` modules lack this sequence entirely.

## Usage Pattern

```
Battery boot   → Eco (0W, no dGPU available)
Plug AC        → Standard tried, "reboot needed" logged
Use laptop on AC until you need the dGPU
Reboot when ready → dGPU available
```

The key insight: **eco works perfectly** (0W, immediate, no side effects). The reboot tax is only paid when you want the dGPU back. For most battery-on-the-go use, you'll reboot once when plugging back into AC, then the GPU is available until the next battery cycle.

## Testing

```bash
# Manual eco
sudo dgpu-switch.sh eco
cat /sys/devices/platform/asus-nb-wmi/dgpu_disable  # → 1
nvidia-smi                                            # → No devices found

# Restore (requires reboot)
sudo dgpu-switch.sh standard
cat /sys/devices/platform/asus-nb-wmi/dgpu_disable  # → 0
# → Reboot now

# After reboot, verify
dgpu-switch.sh status
nvidia-smi                                            # → RTX 5090 visible
```

## Links

- [NVIDIA open-gpu-kernel-modules issue #1064](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1064) — GSP heartbeat lost on GC6 exit
- [nova-core GSP unload patches](https://lore.gitlab.freedesktop.org/drm-ai-reviews/20260515-nova-unload-v5-3-c4d6250ad160@nvidia.com/) — proper cleanup sequence
- [Blackwell VBIOS reset bug](https://yhbt.net/lore/dri-devel/20260422-nova-unload-v3-6-1d2c81bd3ced@nvidia.com/t/) — documented in nova-core patch cover letter
