# Power Optimization Modules

Modular, independently testable components for Zephyrus G16 power management.

## Quick Start

```bash
# Check status of all modules
./test-all.sh status

# Preview battery mode changes (dry-run)
./test-all.sh battery

# Preview AC mode changes (dry-run)
./test-all.sh ac

# Apply battery mode (requires root)
sudo ./test-all.sh apply-battery

# Apply AC mode (requires root)
sudo ./test-all.sh apply-ac
```

## Individual Modules

Each module can be tested independently:

| Module | Description | Battery Action | AC Action |
|--------|-------------|----------------|-----------|
| `cpu-cores.sh` | Core offlining | 7 cores (cpu0,6-9,14-15) | All 16 cores |
| `cpu-power.sh` | RAPL, turbo, EPP | 3W cap, no turbo, EPP=power | 110W, turbo on, EPP=perf |
| `pci-power.sh` | PCIe ASPM, runtime PM | powersupersave, auto (GPU excluded) | default, on |
| `kernel-tunables.sh` | NMI, writeback | NMI off, 15s writeback | NMI on, 5s writeback |
| `audio.sh` | HDA codec PM | 60s power-save | Always on |
| `usb.sh` | USB autosuspend | 2s (skip HID) | Disabled |
| `network.sh` | WiFi/Bluetooth | WiFi PS on, BT off | WiFi PS off, BT on |
| `display.sh` | Refresh rate | 60Hz | 165Hz |
| `gpu.sh` | GPU mode verify | Check Hybrid+suspended | Check Hybrid |
| `platform.sh` | ACPI profile | quiet (via asusctl) | performance |

## Testing a Single Module

```bash
# Status
./cpu-cores.sh status

# Dry-run (preview changes)
sudo ./cpu-cores.sh battery --dry-run

# Apply
sudo ./cpu-cores.sh battery
```

## Module Dependencies

All modules source `common.sh` for shared functionality:
- `log()` / `warn()` — Logging
- `sysfs_write()` — Safe sysfs writes with dry-run support
- `require_root()` — Root check
- `parse_module_args()` — Argument parsing

## Power Impact Estimates

| Module | Battery Savings |
|--------|-----------------|
| cpu-cores | ~0.5-1W |
| cpu-power (RAPL) | ~1-2W |
| pci-power | ~0.3-0.5W |
| audio | ~0.1W |
| usb | ~0.1-0.2W |
| network (WiFi) | ~0.2W |
| network (BT) | ~0.1W |
| display (60Hz) | ~0.5-1W |

Total potential savings: **~3-5W** at idle

## Notes

- GPU module does NOT auto-switch modes (Integrated is broken on GU605CX)
- Display module needs user session context (may skip if run purely as root)
- asusctl handles some settings automatically (fan curves, charge limit)
