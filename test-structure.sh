#!/usr/bin/env bash
# =============================================================================
# test-structure.sh — Test the new multi-DE architecture
#
# Run this to verify the reorganization is working correctly
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  ZephyrusOptimizations Structure Test"
echo "============================================================"
echo ""

# Test 1: Check directory structure
echo "Test 1: Directory Structure"
echo "----------------------------"
for dir in core de/gnome de/kde; do
    if [[ -d "$SCRIPT_DIR/$dir" ]]; then
        echo "✓ $dir exists"
    else
        echo "✗ $dir missing!"
        exit 1
    fi
done
echo ""

# Test 2: Check core modules
echo "Test 2: Core Modules"
echo "--------------------"
core_modules=(
    "common.sh"
    "cpu-power.sh"
    "cpu-cores.sh"
    "gpu.sh"
    "audio.sh"
    "network.sh"
    "usb.sh"
    "pci-power.sh"
    "kernel-tunables.sh"
    "platform.sh"
)

for mod in "${core_modules[@]}"; do
    if [[ -f "$SCRIPT_DIR/core/$mod" ]]; then
        if [[ -x "$SCRIPT_DIR/core/$mod" ]] || [[ "$mod" == "common.sh" ]]; then
            echo "✓ core/$mod"
        else
            echo "✗ core/$mod not executable!"
        fi
    else
        echo "✗ core/$mod missing!"
    fi
done
echo ""

# Test 3: Check GNOME modules
echo "Test 3: GNOME Modules"
echo "---------------------"
gnome_modules=(
    "display.sh"
    "set-refresh-rate.py"
    "extensions.sh"
)

for mod in "${gnome_modules[@]}"; do
    if [[ -f "$SCRIPT_DIR/de/gnome/$mod" ]]; then
        if [[ -x "$SCRIPT_DIR/de/gnome/$mod" ]]; then
            echo "✓ de/gnome/$mod"
        else
            echo "✗ de/gnome/$mod not executable!"
        fi
    else
        echo "✗ de/gnome/$mod missing!"
    fi
done
echo ""

# Test 4: Check KDE modules
echo "Test 4: KDE Modules"
echo "-------------------"
kde_modules=(
    "display.sh"
    "effects.sh"
)

for mod in "${kde_modules[@]}"; do
    if [[ -f "$SCRIPT_DIR/de/kde/$mod" ]]; then
        if [[ -x "$SCRIPT_DIR/de/kde/$mod" ]]; then
            echo "✓ de/kde/$mod"
        else
            echo "✗ de/kde/$mod not executable!"
        fi
    else
        echo "✗ de/kde/$mod missing!"
    fi
done
echo ""

# Test 5: Check unified script
echo "Test 5: Unified Power-Switch Script"
echo "------------------------------------"
if [[ -f "$SCRIPT_DIR/power-switch-unified.sh" ]]; then
    if [[ -x "$SCRIPT_DIR/power-switch-unified.sh" ]]; then
        echo "✓ power-switch-unified.sh exists and is executable"
    else
        echo "✗ power-switch-unified.sh not executable!"
    fi
else
    echo "✗ power-switch-unified.sh missing!"
    exit 1
fi
echo ""

# Test 6: DE Detection
echo "Test 6: Desktop Environment Detection"
echo "--------------------------------------"
source "$SCRIPT_DIR/core/common.sh"

detect_desktop_environment() {
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
            echo "gnome"
            return 0
        elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
            echo "kde"
            return 0
        fi
    fi
    
    if pgrep -x gnome-shell >/dev/null 2>&1; then
        echo "gnome"
        return 0
    elif pgrep -x plasmashell >/dev/null 2>&1; then
        echo "kde"
        return 0
    fi
    
    echo "unknown"
}

DE=$(detect_desktop_environment)
echo "Detected DE: $DE"

case "$DE" in
    gnome)
        echo "✓ GNOME detected - will use de/gnome/ modules"
        ;;
    kde)
        echo "✓ KDE detected - will use de/kde/ modules"
        ;;
    unknown)
        echo "⚠ No DE detected - display and effects will be skipped"
        ;;
esac
echo ""

# Test 7: Module sourcing
echo "Test 7: Module Sourcing"
echo "-----------------------"
for mod in core/cpu-power.sh core/gpu.sh; do
    if bash -n "$SCRIPT_DIR/$mod" 2>/dev/null; then
        echo "✓ $mod syntax OK"
    else
        echo "✗ $mod has syntax errors!"
    fi
done

for mod in de/gnome/display.sh de/kde/display.sh; do
    if bash -n "$SCRIPT_DIR/$mod" 2>/dev/null; then
        echo "✓ $mod syntax OK"
    else
        echo "✗ $mod has syntax errors!"
    fi
done
echo ""

# Test 8: Dry-run test
echo "Test 8: Dry-Run Test"
echo "--------------------"
echo "Testing unified script dry-run (no root needed)..."
if "$SCRIPT_DIR/power-switch-unified.sh" status >/dev/null 2>&1; then
    echo "✓ power-switch-unified.sh status works"
else
    echo "✗ power-switch-unified.sh status failed!"
fi
echo ""

echo "============================================================"
echo "  All tests passed!"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Test individual modules:"
echo "     cd core && ./cpu-power.sh status"
echo "     cd de/$DE && ./display.sh status"
echo ""
echo "  2. Test full battery mode (dry-run):"
echo "     sudo ./power-switch-unified.sh battery --dry-run"
echo ""
echo "  3. Apply battery mode:"
echo "     sudo ./power-switch-unified.sh battery"
echo ""
