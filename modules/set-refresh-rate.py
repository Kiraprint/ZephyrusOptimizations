#!/usr/bin/env python3
"""
set-refresh-rate.py — Set display refresh rate on GNOME/Wayland via Mutter D-Bus API

Usage:
    ./set-refresh-rate.py 240          # Set 240Hz
    ./set-refresh-rate.py 60           # Set 60Hz
    ./set-refresh-rate.py --list       # List available modes
    ./set-refresh-rate.py --current    # Show current mode
"""

import sys
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

DISPLAY_CONFIG_INTERFACE = "org.gnome.Mutter.DisplayConfig"
DISPLAY_CONFIG_OBJECT_PATH = "/org/gnome/Mutter/DisplayConfig"

def get_display_config_proxy():
    """Get D-Bus proxy for Mutter DisplayConfig"""
    return Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION,
        Gio.DBusProxyFlags.NONE,
        None,
        DISPLAY_CONFIG_INTERFACE,
        DISPLAY_CONFIG_OBJECT_PATH,
        DISPLAY_CONFIG_INTERFACE,
        None
    )

def get_current_state(proxy):
    """Get current monitor configuration"""
    result = proxy.call_sync(
        "GetCurrentState",
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None
    )
    return result.unpack()

def apply_config(proxy, serial, logical_monitors, properties={}):
    """Apply monitor configuration"""
    # Method 1 = persistent, 2 = temporary (ask user)
    method = 1
    
    params = GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (
        serial,
        method,
        logical_monitors,
        properties
    ))
    
    proxy.call_sync(
        "ApplyMonitorsConfig",
        params,
        Gio.DBusCallFlags.NONE,
        -1,
        None
    )

def parse_modes(monitors):
    """Parse available modes from monitor data"""
    modes = []
    for monitor in monitors:
        connector_info, mode_list, props = monitor
        connector, vendor, product, serial_num = connector_info
        
        for mode in mode_list:
            mode_id, width, height, refresh, scale, scales, mode_props = mode
            is_current = mode_props.get('is-current', False)
            is_preferred = mode_props.get('is-preferred', False)
            
            modes.append({
                'connector': connector,
                'mode_id': mode_id,
                'width': width,
                'height': height,
                'refresh': refresh,
                'scale': scale,
                'scales': scales,
                'is_current': is_current,
                'is_preferred': is_preferred,
                'props': mode_props
            })
    
    return modes

def list_modes():
    """List all available display modes"""
    proxy = get_display_config_proxy()
    serial, monitors, logical_monitors, properties = get_current_state(proxy)
    
    modes = parse_modes(monitors)
    
    print("Available modes:")
    current_mode = None
    for m in modes:
        marker = ""
        if m['is_current']:
            marker = " (current)"
            current_mode = m
        elif m['is_preferred']:
            marker = " (preferred)"
        
        print(f"  {m['connector']}: {m['width']}x{m['height']} @ {m['refresh']:.2f}Hz{marker}")
    
    return current_mode

def get_current_mode():
    """Get current display mode"""
    proxy = get_display_config_proxy()
    serial, monitors, logical_monitors, properties = get_current_state(proxy)
    
    modes = parse_modes(monitors)
    
    for m in modes:
        if m['is_current']:
            return m
    
    return None

def set_refresh_rate(target_refresh):
    """Set display refresh rate"""
    proxy = get_display_config_proxy()
    serial, monitors, logical_monitors, properties = get_current_state(proxy)
    
    modes = parse_modes(monitors)
    
    # Find current mode
    current = None
    for m in modes:
        if m['is_current']:
            current = m
            break
    
    if not current:
        print("Error: Could not find current mode")
        return False
    
    # Find target mode with same resolution but different refresh
    target = None
    for m in modes:
        if (m['width'] == current['width'] and 
            m['height'] == current['height'] and
            abs(m['refresh'] - target_refresh) < 1.0):
            target = m
            break
    
    if not target:
        print(f"Error: Could not find mode with {current['width']}x{current['height']} @ {target_refresh}Hz")
        print("Available refresh rates:")
        for m in modes:
            if m['width'] == current['width'] and m['height'] == current['height']:
                print(f"  {m['refresh']:.2f}Hz")
        return False
    
    if target['is_current']:
        print(f"Already at {target_refresh}Hz")
        return True
    
    # Build new logical monitor config
    # Format: (x, y, scale, transform, is_primary, [(connector, mode_id, properties)])
    new_logical_monitors = []
    
    for lm in logical_monitors:
        x, y, scale, transform, is_primary, monitor_configs, lm_props = lm
        
        new_monitor_configs = []
        for mc in monitor_configs:
            connector, vendor, product, serial_num = mc
            
            # Use target mode for our connector
            if connector == target['connector']:
                mode_str = target['mode_id']
            else:
                # Keep other monitors at their current mode
                for m in modes:
                    if m['connector'] == connector and m['is_current']:
                        mode_str = m['mode_id']
                        break
            
            new_monitor_configs.append((connector, mode_str, {}))
        
        new_logical_monitors.append((x, y, scale, transform, is_primary, new_monitor_configs))
    
    # Apply the new config
    try:
        apply_config(proxy, serial, new_logical_monitors)
        print(f"Refresh rate set to {target['refresh']:.0f}Hz")
        return True
    except Exception as e:
        print(f"Error applying config: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    
    arg = sys.argv[1]
    
    if arg == "--list":
        list_modes()
        return 0
    elif arg == "--current":
        mode = get_current_mode()
        if mode:
            print(f"{mode['width']}x{mode['height']} @ {mode['refresh']:.2f}Hz")
        else:
            print("Could not detect current mode")
        return 0
    else:
        try:
            target_refresh = float(arg)
            if set_refresh_rate(target_refresh):
                return 0
            else:
                return 1
        except ValueError:
            print(f"Invalid argument: {arg}")
            print(__doc__)
            return 1

if __name__ == "__main__":
    sys.exit(main())
