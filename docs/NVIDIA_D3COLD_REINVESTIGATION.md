# NVIDIA dGPU "D3cold bus removal" reinvestigation (2026-08-10)

Supersedes the mechanism section of `NVIDIA_D3_REMOVAL_EVIDENCE.md`. That
document's *observations* were correct; its *conclusion* ("platform/EC removes
the device from the PCI bus") is **disproven**. Live reproduction shows the
device is never removed — cardwire's eBPF LSM hides the whole dGPU subtree
from userspace, which *looks* like a silent bus removal.

System: ASUS ROG Zephyrus G16 GU605CX, kernel 7.2.0-rc6-1-cachyos-rc,
nvidia-open 610.57.04, cardwire 0.11.1, GPU 10de:2c58 @ 0000:01:00.0.

## Reproduction (fresh, self-instrumented, 2026-08-10 18:06 / 18:14)

`cardwire set integrated` from Hybrid, with a 50–300 ms sysfs poller,
`udevadm monitor`, and the driver's own procfs view:

| t | GPU 01:00.0 | root port 00:01.0 | audio 01:00.1 | dgpu_disable | gpu_mux_mode |
|---|---|---|---|---|---|
| before | D0, runtime active | present | present | 0 | 1 |
| +<300 ms | **dir missing** | **dir missing** | **dir missing** | 0 (unchanged) | 1 (unchanged) |

But simultaneously:

- **udevadm monitor: zero PCI events** (the tool works — it captured real USB
  remove uevents in the same run). A kernel `device_unregister` always emits a
  KOBJ_REMOVE uevent; none arrived. `/var/log/zephyrus-dgpu.log` (udev
  `ACTION=="remove"` handler) untouched since boot.
- **dmesg: zero messages** at the event (no AER, DPC, pciehp, link-down,
  NVRM). 7.2-rc6 kernel, nothing logged.
- **Driver never notified**: `/proc/driver/nvidia/gpus/0000:01:00.0/power`
  stays readable, "Video Memory: Active", MSI-X vectors alive in
  `/proc/interrupts` (irq 216 count still incrementing).
- **Device still registered in the kernel**: `ls /sys/kernel/iommu_groups/17/devices/`
  → `0000:01:00.0`, `0000:01:00.1`; group 2 → `0000:00:01.0`. IOMMU group
  dirs are created/destroyed with device add/remove — the devices are there.
- nvidia-smi fails with "couldn't communicate" — because opening
  `/dev/nvidiactl` returns **ENOENT** (eBPF), not because the GPU is gone.
- Recovery `cardwire set hybrid` re-shows all three devices instantly; no
  re-probe, no dmesg, driver state continuous. Nothing was ever re-enumerated
  because nothing was ever removed.

**Conclusion: the sysfs/lspci "disappearance" is cardwire's eBPF program
lying to userspace. The dGPU stays on the bus, in D0, fully powered and
functional.** This also explains the old kprobe evidence perfectly: zero
events on `nv_pmops_runtime_suspend`, `nv_pci_remove`,
`nv_acpi_d3cold_dsm_for_upstream_port` — because **no driver or kernel code
path ever ran**. The probes were correct; the interpretation wasn't.

## Why it looks like removal — the cardwire code path

`crates/cardwire-daemon/src/core/inode.rs::get_inodes()` collects the inodes
of, per GPU:

- `/dev/dri/card1`, `/dev/dri/renderD128`
- `/sys/bus/pci/devices/0000:01:00.0` (both the symlink and the target dir),
  the audio function `0000:01:00.1`, **and the whole parent chain**
  (`pci_to_inode` walks up: root port `0000:00:01.0`, host bridge
  `0000:00:00.0`)
- `/sys/class/drm/card1*` / `renderD128*` entries, hwmon, `/dev/nvidia0`,
  `/sys/class/backlight/nvidia_0`

`interface/gpu.rs::block_gpu()` inserts them into the eBPF map
`CW_BLOCKED_INO` (blocked=1). The eBPF program
(`crates/cardwire-ebpf/src/main.rs`) then:

- `file_open` / `inode_permission` / `inode_getattr` LSM hooks → **ENOENT**
  for any blocked inode (stat, open, permission checks all fail)
- `sys_exit_getdents64` tracepoint **rewrites userspace readdir output** to
  hide blocked entries — so `ls /sys/bus/pci/devices/`, `ls /dev/dri/`,
  `lspci` never see them at all.

Because the parent chain (root port, host bridge) is blocked too, the *whole
dGPU subtree* vanishes from every sysfs walk — indistinguishable from bus
removal without cross-checking non-VFS views (IOMMU groups, /proc/interrupts,
udev).

## What cardwire actually does per mode (code-grounded)

`crates/cardwire-daemon/src/interface/mode.rs::apply_mode()`:

**Integrated** (`Modes::Integrated | Smart`): for every available discrete,
non-default GPU → `gpu.block_gpu(id)` (eBPF map insert, above) →
`update_mode_bpf_map(INTEGRATED)` → emit signals →
`send_drm_uevent(card1)` (write `"change"` to `/sys/class/drm/card1/uevent`)
→ `restart_nvidia_powerd()` (`systemctl restart --no-block`, only if
enabled). **That is all. No sysfs PCI writes, no `dgpu_disable`, no ACPI, no
MUX, no power management of any kind.**

**Hybrid**: for every available GPU → `gpu.unblock_gpu()` (map entries kept,
`blocked=0`) → mode map = HYBRID → signals + DRM uevent + nvidia-powerd
restart. The LSM hooks short-circuit on `is_hybrid()` → SUCCESS, so all GPU
files are immediately accessible again. DRM "change" uevent makes the display
server rescan connectors; nvidia-powerd restart re-attaches power management.

Battery auto-switch (`tasks/battery_switch.rs`): UPower `on_battery=true` →
`internal_set_mode(Integrated)`; AC → configured mode (this system: hybrid).

## Is it kernel-side or nvidia-open-side?

**Neither performs the claimed "removal" — it does not exist.** Splitting the
real problems:

1. **"Can't communicate with the dGPU in integrated mode"** — cardwire's
   eBPF ENOENT, by design. Not a driver or kernel bug.

2. **"dGPU stays at D0" (no real power saving)** — the actual issue. Two
   compounding causes:
   - cardwire only gates *access*; nothing ever requests D3cold. `dgpu_disable`
     stays 0, MUX untouched, no PCI PM writes.
   - The nvidia driver's own RTD3 self-idle (fine-grained, DPM=0x02, "Runtime
     D3 status: Enabled (fine-grained)") never completes GC6 entry on this
     platform even with zero clients for minutes. Per
     `src/nvidia/arch/nvalloc/unix/src/dynamic-power.c`:
     `RmGcxPowerManagement` uses GC6 only if `PDB_PROP_GPU_RTD3_GC6_SUPPORTED
     && gc6_upstream_port_configured`; the latter requires the PEX `_DSM`
     (`RmConfigureUpstreamPortForRTD3` → `nv_acpi_d3cold_dsm_for_upstream_port`),
     which the kprobe evidence shows is never used on this box. GC6 unusable →
     fallback GCOFF needs used FB ≤ `gcoff_max_fb_size` (1 GiB) and zero
     `clients_gcoff_disallow_refcount`; engine-idle prerequisites must all
     pass. On this GPU/firmware the chain never fires (no RM GC6/RTD3 logs
     with `NVreg_EnableStreamDebug=1`). Net: driver-side RTD3 is effectively
     unavailable here — an nvidia-open/platform-firmware gap, not a kernel
     bug.

3. **The one mechanism that does cut dGPU power on this laptop is the ASUS
   EC rail cut**: `/sys/devices/platform/asus-nb-wmi/dgpu_disable=1`
   (`dgpu-switch.sh eco`, measured 0 W — see `GPU_POWER_SWITCH.md`). That is
   real D3cold. Its limitation (reboot required to re-bind nvidia-open) is
   NVIDIA's GSP-heartbeat-on-GC6-exit bug
   (open-gpu-kernel-modules #1064) + Blackwell VBIOS PCI-reset bug — again
   nvidia-side, not kernel-side.

## Side effects on the existing repo work

- The idle watchdog patch (`open-gpu-kernel-modules` local commits `f854a8a`,
  `442aee3`) never fires on this platform: `device_is_registered()` stays true
  because the device is never unregistered. Harmless, but a no-op — the
  premised "silent bus loss" does not occur.
- `core/gpu.sh` header comment "D3cold = bus removal: communication dies,
  driver freezes in D0" describes a non-event. The freeze it guards against is
  actually caused by nvidia-powerd/NVML attaching to a device whose sysfs is
  eBPF-hidden — the guard drop-in for nvidia-powerd is still the right
  mitigation, just for a different reason.
- `nvidia-powerd` restart on every mode switch + the eBPF block means
  nvidia-powerd dies on integrated (can't open `/dev/nvidia*` → "Error(1f)…
  Quit") and must be restarted on hybrid — keep the guard wrapper.

## How to verify on any machine (no root needed except the switch)

1. `cardwire set integrated`
2. `ls /sys/kernel/iommu_groups/*/devices/ | grep 01:00` → still listed
3. `grep nvidia /proc/interrupts` → vectors alive
4. `udevadm monitor` during the switch → no PCI remove uevents
5. `cardwire set hybrid`

## Open items

- Why GC6 entry never completes (which precondition blocks) — would need RM
  debug logs at `NVreg_EnableStreamDebug=1` + full NVreg RM logging or a
  kernel-built-in probe on the RM side; not needed to explain the observed
  behavior.
- Whether `PDB_PROP_GPU_RTD3_RG_SUPPORTED` (non-ACPI RTD3) is set on
  GB203M — if it is, the RG path is the one to inspect for the D0-stuck
  behavior.
