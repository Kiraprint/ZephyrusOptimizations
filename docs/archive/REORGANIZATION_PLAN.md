# Project Reorganization Plan

## Current State
- All modules are mixed together
- Display management hardcoded for GNOME/Mutter
- Extension management GNOME-specific
- No separation between core and DE-specific code

## Goal
Support multiple Desktop Environments (GNOME, KDE) with shared core functionality.

## New Structure

```
ZephyrusOptimizations/
├── core/                       # DE-agnostic core functionality
│   ├── common.sh               # Shared helpers (from modules/common.sh)
│   ├── cpu-power.sh            # CPU power management (turbo, EPP, RAPL)
│   ├── cpu-cores.sh            # CPU core management
│   ├── gpu.sh                  # GPU power management (supergfxctl)
│   ├── audio.sh                # Audio codec power-save
│   ├── network.sh              # WiFi/Bluetooth power management
│   ├── usb.sh                  # USB autosuspend
│   ├── pci-power.sh            # PCIe ASPM, runtime PM
│   ├── kernel-tunables.sh      # NMI watchdog, VM writeback
│   ├── platform.sh             # Platform profile (asusctl)
│   └── browser-brave.sh        # Browser optimizations
│
├── de/                         # Desktop Environment specific modules
│   ├── gnome/
│   │   ├── display.sh          # GNOME display management (Mutter D-Bus)
│   │   ├── set-refresh-rate.py # Python script for Mutter
│   │   └── extensions.sh       # GNOME extension management
│   │
│   └── kde/
│       ├── display.sh          # KDE display management (kscreen-doctor)
│       └── effects.sh          # KDE effects management (kwriteconfig5)
│
├── power-switch.sh             # Main orchestrator (detect DE, call appropriate modules)
├── power-monitor.sh            # Power monitoring script
├── README.md                   # Updated documentation
├── PLAN.md                     # Technical details
└── DISPLAY-INFO.md             # Display configuration
```

## Migration Steps

### Phase 1: Create New Structure
1. Create `core/` and `de/gnome/`, `de/kde/` directories
2. Move DE-agnostic modules to `core/`
3. Move GNOME-specific modules to `de/gnome/`
4. Create KDE-specific modules in `de/kde/`

### Phase 2: Abstract Display Management
Create a unified interface:
- `de/gnome/display.sh` - Uses Mutter D-Bus API (existing)
- `de/kde/display.sh` - Uses kscreen-doctor
- Both expose same interface: `{battery|ac|status}`

### Phase 3: Abstract DE-Specific Features
- GNOME: Extensions management (blur-my-shell)
- KDE: Effects management (blur, animations)

### Phase 4: Update Main Script
Modify `power-switch.sh` to:
1. Detect current DE (XDG_CURRENT_DESKTOP)
2. Source appropriate DE-specific modules
3. Call core modules (same for all DEs)

### Phase 5: Update Documentation
- Update README.md with multi-DE support
- Document DE-specific requirements
- Add troubleshooting section for each DE

## DE Detection

```bash
detect_desktop_environment() {
    if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
        echo "gnome"
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
        echo "kde"
    else
        echo "unknown"
    fi
}
```

## KDE-Specific Implementation Notes

### Display Management
- Use `kscreen-doctor` for refresh rate control
- Command: `kscreen-doctor output.1.mode.refresh=240`
- Check with: `kscreen-doctor -o`

### Effects Management
- Use `kwriteconfig5` to toggle effects
- Battery: Disable blur, reduce animations
- AC: Enable full effects
- Files: `~/.config/kwinrc`

### Session Detection
- Use `qdbus` instead of `gdbus`
- Check `org.kde.KWin` for display config

## Compatibility Matrix

| Feature | GNOME | KDE | Implementation |
|---------|-------|-----|----------------|
| CPU Power | ✅ | ✅ | Core module (DE-agnostic) |
| GPU Power | ✅ | ✅ | Core module (supergfxctl) |
| Display Refresh | ✅ | ✅ | DE-specific module |
| Visual Effects | ✅ (extensions) | ✅ (kwin effects) | DE-specific module |
| Network | ✅ | ✅ | Core module (iw, bluetoothctl) |
| USB/Audio | ✅ | ✅ | Core module (sysfs) |
| Platform | ✅ | ✅ | Core module (asusctl) |

## Testing Strategy

1. Test core modules independently (same on both DEs)
2. Test DE-specific modules in isolation
3. Test full battery→ac→battery cycle on GNOME
4. Test full battery→ac→battery cycle on KDE
5. Verify power consumption is similar on both DEs

## Backward Compatibility

Keep symlinks in `modules/` pointing to new locations for transition period:
```bash
modules/cpu-power.sh -> ../core/cpu-power.sh
modules/display.sh -> ../de/gnome/display.sh  # or kde based on DE
```
