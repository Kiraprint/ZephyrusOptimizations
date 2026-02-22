# Display Configuration - OLED 240Hz VRR Panel

## Hardware: Samsung ATNA60DL01-0 (GU605CX)

**Panel Specs:**
- Resolution: 2560x1600 (16:10)
- Technology: OLED (true black = pixels off)
- Native refresh: 240Hz
- VRR range: 48-240Hz (Adaptive Sync / FreeSync)

## Variable Refresh Rate (VRR) Behavior

Your panel has **two VRR modes**:

### 1. Power-Save Range: 48-60Hz
- GNOME shows this as "48-60Hz variable"
- Panel dynamically adjusts:
  - **48Hz** when idle (desktop, reading, static content)
  - **60Hz** during light interaction (scrolling, typing)
- **This is already optimal for battery** — no need to force 60Hz

### 2. Full Range: 48-240Hz
- Used for gaming and high-performance scenarios
- Adaptive sync matches frame rate (e.g., 90fps game = 90Hz)
- Maximum smoothness for animations and scrolling

## Current Configuration

**GNOME Settings:**
- VRR enabled: Yes (`experimental-features: variable-refresh-rate`)
- Current mode: Variable (adaptive 48-240Hz)
- On battery: Auto-throttles to 48-60Hz range
- On AC: Full 48-240Hz range available

## Power Optimization Scripts

### Battery Mode
```bash
# Sets max refresh to 60Hz
# VRR will drop to 48Hz when idle automatically
./modules/display.sh battery
```

**Power savings:** ~0.5-1W compared to 240Hz constant

### AC Mode
```bash
# Sets max refresh to 240Hz
# Full VRR range 48-240Hz available
./modules/display.sh ac
```

## Important Notes

1. **Don't disable VRR** — It provides automatic power savings by dropping to 48Hz when idle

2. **OLED power characteristics:**
   - Refresh rate: Moderate impact (~0.5-1W difference 48Hz vs 240Hz)
   - Content brightness: High impact (bright white = high power)
   - True black pixels: Zero power (OLED pixels off)
   - **Recommendation**: Use dark themes for max battery life

3. **GNOME Wayland:** Display settings are controlled via D-Bus API, not xrandr

4. **Minimum 48Hz:** This is the lowest your panel goes in VRR mode — perfectly normal and saves power

## Verification Commands

```bash
# Check available modes
cat /sys/class/drm/card0-eDP-2/modes

# Check EDID VRR range
cat /sys/class/drm/card0-eDP-2/edid | edid-decode | grep -i "refresh\|range"

# Check GNOME VRR status
gsettings get org.gnome.mutter experimental-features

# Current refresh rate
gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.gnome.Mutter.DisplayConfig.GetCurrentState
```

## Summary

✅ **Your 48-60Hz variable mode is correct and optimal for battery**
✅ VRR automatically drops to 48Hz when idle (max savings)
✅ Ramps to 60Hz during use (responsive)
✅ Can go up to 240Hz on AC for gaming/smooth scrolling

**No action needed** — GNOME's VRR is already working perfectly for power optimization.
