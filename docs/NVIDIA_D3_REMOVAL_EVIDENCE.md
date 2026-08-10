NVIDIA dGPU silent bus-removal evidence
=======================================
System: ASUS ROG Zephyrus G16 GU605CX (Intel Arrow Lake + NVIDIA RTX 5090 Laptop)
Kernel: 7.2.0-rc6-1-cachyos-rc
Driver: nvidia-open 610.57.04 (KMD open modules)
GPU: 10de:2c58 at 0000:01:00.0, root port 0000:00:01.0

SYMPTOM
-------
Switching GPU mode to "integrated" (via cardwire, which is supergfxctl's
successor and manages the ASUS MUX) makes the dGPU disappear from the PCI
bus within 1-2 seconds. The device is removed silently:
  - lspci no longer lists 0000:01:00.0 / 0000:00:01.0
  - /sys/bus/pci/devices/0000:01:00.0 is gone
  - the nvidia driver is never notified: /proc/driver/nvidia/gpus/0000:01:00.0
    stays registered forever, /dev/nvidia0..nvidiactl persist, and the power
    state freezes at "Runtime D3 status: Enabled (fine-grained)" +
    "Video Memory: Active". The rail stays powered (GPU temp stays ~53C,
    nvidia-smi on AC shows ~20W draw while the device is "gone").
Replug AC / switching back to "hybrid" restores the device (re-enumerates,
driver re-binds) without reboot.

KPROBE EVIDENCE (ftrace, armed during the event)
------------------------------------------------
Probes on the nvidia driver's key entry points were live while the device
was removed (2 independent runs):

  p:kprobes/pm_suspend  nv_pmops_runtime_suspend
  p:kprobes/pm_resume   nv_pmops_runtime_resume
  p:kprobes/pci_remove  nv_pci_remove
  p:kprobes/d3cold_dsm  nv_acpi_d3cold_dsm_for_upstream_port

Result: ZERO events fired during the removal.
  - nv_pmops_runtime_suspend was never called  -> removal is NOT a
    driver-initiated runtime D3 (also confirmed: power/control=on does not
    prevent the removal, and nvidia-powerd holding /dev/nvidia0 does not
    prevent it)
  - nv_pci_remove was never called              -> the driver is NOT notified
    of the device loss (no pci_stop/remove path)
  - nv_acpi_d3cold_dsm_for_upstream_port was never called
  - dmesg has ZERO messages at the event time (no link-down, no AER, no DPC,
    no NVRM message, no "GPU has fallen off the bus")

Also: cardwire logs "Switched to Integrated" and restarts nvidia-powerd at
the same second; nvidia-powerd then fails to attach ("Failed to attach all
GPUs / GPU Attach client failed 0x0").

MECHANISM HYPOTHESIS
--------------------
Cardwire's integrated mode drives the ASUS MUX (gpu_mux_mode=1 here). The
EC physically disconnects the dGPU (expected hardware behavior), but the
nvidia driver is left with a stale, non-functional device:
  - no remove callback / no Xid / no recovery attempt
  - /proc/driver/nvidia/gpus entry persists indefinitely
  - power state frozen at "Active" (rail may stay powered)
This stale-state behavior (vs. cleanly handling device loss) is the issue
being reported.

REPRODUCE
---------
1. boot with nvidia-open 610.57.04, Hybrid mode (dGPU on the bus)
2. cardwire set integrated   (or unplug AC: cardwire auto-switches)
3. within ~1-2s: device gone from lspci; driver frozen as described
4. cardwire set hybrid / plug AC: device re-enumerates, driver re-binds

Full logs: nvidia-bug-report.sh output (see attached), dmesg (empty at
event), kprobe trace (0 events), cardwire journal.
