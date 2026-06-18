# Project Structure

## Architecture

The project has been reorganized to support multiple Desktop Environments:

```
├── core/                           # DE-agnostic modules (work on any DE)
│   ├── common.sh                   # Shared helpers (logging, sysfs, DE detection)
│   ├── cpu-power.sh                # CPU turbo, EPP, HWP, RAPL
│   ├── cpu-cores.sh                # CPU core management
│   ├── gpu.sh                      # GPU power (supergfxctl)
│   ├── audio.sh                    # Audio codec power-save
│   ├── network.sh                  # WiFi/Bluetooth
│   ├── usb.sh                      # USB autosuspend (selective, skip HID)
│   ├── pci-power.sh                # PCIe ASPM, runtime PM
│   ├── kernel-tunables.sh          # NMI watchdog, VM writeback
│   ├── platform.sh                 # Platform profile (asusctl)
│   └── browser-brave.sh            # Browser optimizations
│
├── de/                             # Desktop Environment specific
│   ├── gnome/
│   │   ├── display.sh              # GNOME display (Mutter D-Bus API)
│   │   ├── set-refresh-rate.py     # Python script for Mutter
│   │   └── extensions.sh           # GNOME extension management
│   │
│   └── kde/
│       ├── display.sh              # KDE display (kscreen-doctor)
│       └── effects.sh              # KDE effects (kwin, kwriteconfig)
│
├── modules/                        # Legacy location (being phased out)
│   └── *                           # Old scripts still here for compatibility
│
├── power-switch.sh                 # Original GNOME-only orchestrator
├── power-switch-unified.sh         # New multi-DE orchestrator (recommended)
├── power-monitor.sh                # Power monitoring
├── README.md                       # Main documentation
├── PLAN.md                         # Technical details
├── DISPLAY-INFO.md                 # Display config reference
└── REORGANIZATION_PLAN.md          # Architecture overview
```

## Module Classification

### Core (DE-Agnostic)
These modules use standard Linux interfaces (sysfs, systemctl) that work identically across all DEs:
- CPU power management
- GPU power management
- Network power-save (iw, bluetoothctl)
- USB autosuspend
- Audio power-save
- PCIe power management
- Kernel tunables
- Platform profile (asusctl)

### DE-Specific
These modules interact with desktop-specific APIs/tools:
- **GNOME**: Mutter D-Bus API (display), gsettings/gnome-extensions (effects)
- **KDE**: kscreen-doctor (display), kwriteconfig/qdbus (effects)

## Usage

### Unified Multi-DE Script (Recommended)

```bash
# Auto-detects your desktop environment and applies appropriate settings
sudo ./power-switch-unified.sh battery
sudo ./power-switch-unified.sh ac
sudo ./power-switch-unified.sh status

# Dry-run mode (preview changes without applying)
sudo ./power-switch-unified.sh battery --dry-run
```

### Individual Module Testing

```bash
# Test core modules
cd core
./cpu-power.sh status
./gpu.sh status

# Test GNOME-specific modules
cd de/gnome
./display.sh status
./extensions.sh status

# Test KDE-specific modules
cd de/kde
./display.sh status
./effects.sh status
```

### Legacy GNOME-Only Script (Deprecated)

For backward compatibility, the original script still works:

```bash
sudo ./power-switch.sh battery
sudo ./power-switch.sh ac
```

**Note**: The legacy script hardcodes GNOME/Mutter and won't work optimally on KDE.

## DE Detection

The unified script automatically detects your DE:

```bash
detect_desktop_environment() {
    # Checks XDG_CURRENT_DESKTOP environment variable
    # Falls back to process detection (gnome-shell, plasmashell)
    # Returns: "gnome", "kde", or "unknown"
}
```

## Adding Support for a New Desktop Environment

To add support for another DE (e.g., XFCE, Budgie):

1. Create a new directory: `de/xfce/`
2. Implement DE-specific modules:
   - `display.sh` - Refresh rate management
   - `effects.sh` - Visual effects management (if applicable)
3. Update `detect_desktop_environment()` in power-switch-unified.sh
4. Update `load_de_modules()` to set `DE_DISPLAY` and `DE_VISUAL` paths
5. Test the full battery→AC→battery cycle

## Module Interface

All modules follow the same interface:

```bash
./module.sh {battery|ac|status} [--dry-run]

# battery   - Apply power-saving settings
# ac        - Apply full-performance settings
# status    - Show current state (no root needed)
# --dry-run - Preview changes without applying (for battery/ac commands)
```

## Common Helper Functions (core/common.sh)

Available to all modules via `source "$SCRIPT_DIR/../common.sh"`:

```bash
log()                      # Log with prefix
warn()                     # Log warning to stderr
sysfs_write()              # Safe sysfs write with dry-run support
detect_power_source()      # Check if AC or battery
require_root()             # Ensure running as root
parse_module_args()        # Parse battery/ac/status/--dry-run
```

## Testing Strategy

### Per-Module Testing

```bash
# Test a single module
cd core
sudo ./cpu-power.sh battery --dry-run
sudo ./cpu-power.sh battery
./cpu-power.sh status
```

### Full System Testing (Unified Script)

```bash
# Preview all changes (no root needed for --dry-run with dry_run support)
./power-switch-unified.sh battery --dry-run

# Apply battery mode
sudo ./power-switch-unified.sh battery

# Verify current state
./power-switch-unified.sh status

# Switch to AC mode
sudo ./power-switch-unified.sh ac

# Switch back to battery
sudo ./power-switch-unified.sh battery
```

### Verify Module Contributions

Check which modules are being called by looking at output logs:
```
[power-switch] Detected Desktop Environment: kde
[power-switch] --- Core Power Settings ---
[cpu-power] Setting EPP to 'power' on all online cores...
[cpu-power]   [ok] cpu0 EPP
[kde-effects] --- Visual Effects (kde) ---
[kde-effects]   [ok] blurEnabled → false
```

## Module Dependencies

```
power-switch-unified.sh
├── core/common.sh              (required)
├── core/cpu-power.sh
├── core/cpu-cores.sh
├── core/gpu.sh
├── core/audio.sh
├── core/network.sh
├── core/usb.sh
├── core/pci-power.sh
├── core/kernel-tunables.sh
├── core/platform.sh
└── de/{gnome,kde}/*            (one selected based on XDG_CURRENT_DESKTOP)
```

Each module is independently testable but relies on:
- `common.sh` for helper functions
- Standard Linux tools: `sysfs`, `iw`, `bluetoothctl`, etc.

## Backward Compatibility

The original `modules/` directory still contains all scripts. The old `power-switch.sh` still works for GNOME. However:

- New features (multi-DE support) require using `power-switch-unified.sh`
- Long-term, the `modules/` directory will be deprecated
- Core and DE-specific modules in `core/` and `de/` are the canonical versions

## Troubleshooting

**DE not detected?**
```bash
echo $XDG_CURRENT_DESKTOP
pgrep gnome-shell  # or plasmashell
```

**Module not found?**
```bash
ls core/
ls de/gnome/
ls de/kde/
```

**Display settings not applying?**
- GNOME: Ensure Mutter is running (check `gnome-shell` process)
- KDE: Ensure kscreen-doctor is installed: `pacman -S kscreen`

**Effects not working?**
- GNOME: Verify extension is installed and enabled
- KDE: Check kwinrc file and that kwriteconfig/kreadconfig are available

## Performance Notes

- Core modules are identical across DEs (no overhead from DE detection)
- DE detection happens once at script start
- Display and effects modules only run if the appropriate DE is detected
- Typical execution time: < 5 seconds for full mode switch

## Future Improvements

- [ ] Add support for other DEs (XFCE, Budgie, etc.)
- [ ] Create systemd service for automatic power switching
- [ ] Add config file for customizing which modules to run
- [ ] Performance profiling and benchmarking tools
- [ ] Integration tests for CI/CD
