#!/usr/bin/env bash
# =============================================================================
# power-switch.sh — Dual-mode power management for ASUS ROG Zephyrus G16
#
# Usage:
#   sudo ./power-switch.sh battery      # Apply battery optimizations
#   sudo ./power-switch.sh ac           # Apply AC / beast mode
#   sudo ./power-switch.sh status       # Show current state (no root needed)
#   sudo ./power-switch.sh battery --dry-run   # Preview without applying
#   sudo ./power-switch.sh ac --dry-run        # Preview without applying
#
# For modular testing, see: ./modules/README.md
#   ./modules/test-all.sh status        # Status of all modules
#   ./modules/cpu-cores.sh battery --dry-run  # Test individual module
#
# Safety:
#   - CPU 0 is NEVER offlined
#   - All changes are reversible via the opposite mode
#   - --dry-run previews every change before applying
#   - Every write to sysfs checks the path exists first
#   - USB autosuspend skips HID devices (keyboard/mouse)
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
# Core offlining DISABLED - Intel Thread Director + RAPL is more efficient
# Testing showed offlining cores doesn't save power on Arrow Lake due to:
#   1. Idle cores already in deep C-states (near 0W)
#   2. Scheduler overhead increases with fewer cores
#   3. Thread Director handles core selection optimally
# PCORE_OFFLINE=(1 2 3 4 5)
# ECORE_OFFLINE=(10 11 12 13)
# LPECORE_OFFLINE=(14 15)

WIFI_IFACE="wlan0"
AC_SUPPLY="/sys/class/power_supply/ACAD/online"

# RAPL power limits (in microwatts)
# Intel 285H specs: PBP=45W, MTP=115W, Min Assured=35W
# Testing showed: 5W=laggy, 10W=responsive, diminishing returns above 12W
RAPL_PL1_BATTERY=8000000     # 8W long-term (power save, still usable)
RAPL_PL2_BATTERY=20000000    # 20W short-term (for UI responsiveness)
# AC: restore full power
RAPL_PL1_AC=110000000        # 110W long-term
RAPL_PL2_AC=110000000        # 110W short-term
# Sysfs paths
RAPL_PL1="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw"
RAPL_PL2="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/constraint_1_power_limit_uw"

DRY_RUN=false
LOG_PREFIX="[power-switch]"

# --- Helpers -----------------------------------------------------------------

log() {
    echo "$LOG_PREFIX $*"
}

warn() {
    echo "$LOG_PREFIX WARNING: $*" >&2
}

# Safe write: checks path exists, optionally dry-runs
sysfs_write() {
    local path="$1"
    local value="$2"
    local description="${3:-$path}"

    if [[ ! -e "$path" ]]; then
        warn "Path does not exist, skipping: $path"
        return 0
    fi

    local current
    current=$(cat "$path" 2>/dev/null) || current="(unreadable)"

    # Handle sysfs files that show options with active one in [brackets]
    # e.g. "[default] performance powersave powersupersave"
    if [[ "$current" == *"[$value]"* ]] || [[ "$current" == "$value" ]]; then
        log "  [skip] $description — already '$value'"
        return 0
    fi

    if $DRY_RUN; then
        log "  [dry-run] $description: '$current' → '$value'"
    else
        if echo "$value" | tee "$path" > /dev/null 2>&1; then
            log "  [ok] $description: '$current' → '$value'"
        else
            warn "Failed to write '$value' to $path (was '$current')"
        fi
    fi
}

# Offline or online a CPU core (never cpu0)
cpu_set_online() {
    local cpu_num="$1"
    local state="$2"  # 0=offline, 1=online

    if [[ "$cpu_num" -eq 0 ]]; then
        warn "Refusing to change cpu0 state — boot CPU must stay online"
        return 0
    fi

    local path="/sys/devices/system/cpu/cpu${cpu_num}/online"
    local state_word="offline"
    [[ "$state" == "1" ]] && state_word="online"

    sysfs_write "$path" "$state" "cpu${cpu_num} → ${state_word}"
}

# Set EPP on all ONLINE cores
set_epp_all() {
    local epp="$1"
    log "Setting EPP to '$epp' on all online cores..."
    for epp_path in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        local cpu_num
        cpu_num=$(echo "$epp_path" | grep -oP 'cpu\K[0-9]+')
        local online_path="/sys/devices/system/cpu/cpu${cpu_num}/online"

        # cpu0 has no 'online' file — it's always online
        if [[ -f "$online_path" ]]; then
            local is_online
            is_online=$(cat "$online_path" 2>/dev/null)
            [[ "$is_online" != "1" ]] && continue
        fi

        sysfs_write "$epp_path" "$epp" "  cpu${cpu_num} EPP"
    done
}

# USB autosuspend — skip HID devices
usb_autosuspend() {
    local timeout="$1"  # seconds, or -1 to disable
    local description="USB autosuspend → ${timeout}s"
    [[ "$timeout" == "-1" ]] && description="USB autosuspend → disabled"

    log "$description (skipping HID devices)..."
    for dev_power in /sys/bus/usb/devices/*/power/autosuspend; do
        local dev_dir
        dev_dir=$(dirname "$(dirname "$dev_power")")
        local dev_name
        dev_name=$(basename "$dev_dir")

        # Skip HID devices (keyboards, mice, touchpads)
        if [[ -d "$dev_dir" ]]; then
            local is_hid=false
            for intf in "$dev_dir"/"${dev_name}":*/bInterfaceClass; do
                if [[ -f "$intf" ]]; then
                    local class
                    class=$(cat "$intf" 2>/dev/null)
                    # Class 03 = HID
                    if [[ "$class" == "03" ]]; then
                        is_hid=true
                        break
                    fi
                fi
            done

            if $is_hid; then
                log "  [skip-hid] $dev_name (HID device, not touching)"
                continue
            fi
        fi

        sysfs_write "$dev_power" "$timeout" "  $dev_name autosuspend"
    done
}

# Set display refresh rate
set_refresh_rate() {
    local rate="$1"
    log "Display refresh rate → ${rate}Hz"
    
    # Detect logged-in user for running user-session commands
    local display_user
    display_user=$(who | grep -E '(:0|tty)' | head -1 | awk '{print $1}')
    
    if [[ -z "$display_user" ]]; then
        log "  [skip] Cannot detect display user (no active session)"
        return 0
    fi
    
    if $DRY_RUN; then
        log "  [dry-run] Would set refresh rate to ${rate}Hz for $display_user"
        return 0
    fi
    
    # Use our Python script via the user's D-Bus session
    local script_path
    script_path="$(dirname "${BASH_SOURCE[0]}")/modules/set-refresh-rate.py"
    
    if [[ -x "$script_path" ]]; then
        # Get user's D-Bus session address
        local dbus_addr
        dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$(pgrep -u "$display_user" gnome-shell | head -1)/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2-)
        
        if [[ -n "$dbus_addr" ]]; then
            local output
            output=$(sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" "$script_path" "$rate" 2>&1)
            if [[ $? -eq 0 ]]; then
                log "  [ok] $output"
                return 0
            else
                log "  [warn] $output"
            fi
        else
            log "  [skip] Cannot detect D-Bus session for $display_user"
        fi
    else
        log "  [skip] set-refresh-rate.py not found at $script_path"
    fi
    
    warn "Failed to set refresh rate"
}

# Toggle GNOME Shell extension
toggle_gnome_extension() {
    local extension_id="$1"
    local action="$2"  # "enable" or "disable"
    
    # Detect logged-in user
    local display_user
    display_user=$(who | grep -E '(:0|tty)' | head -1 | awk '{print $1}')
    
    if [[ -z "$display_user" ]]; then
        log "  [skip] Cannot detect display user"
        return 0
    fi
    
    # Get user's D-Bus session address
    local dbus_addr
    dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$(pgrep -u "$display_user" gnome-shell | head -1)/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2-)
    
    if [[ -z "$dbus_addr" ]]; then
        log "  [skip] Cannot detect D-Bus session for $display_user"
        return 0
    fi
    
    # Check if extension is installed (as the user)
    if ! sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions list 2>/dev/null | grep -q "^${extension_id}$"; then
        log "  [skip] Extension $extension_id not installed"
        return 0
    fi
    
    local current_state
    current_state=$(sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions info "$extension_id" 2>/dev/null | grep -oP 'State:\s+\K\w+')
    
    local target_state="ENABLED"
    [[ "$action" == "disable" ]] && target_state="DISABLED"
    
    if [[ "$current_state" == "$target_state" ]]; then
        log "  [skip] $extension_id already ${action}d"
        return 0
    fi
    
    if $DRY_RUN; then
        log "  [dry-run] Would $action $extension_id"
        return 0
    fi
    
    if sudo -u "$display_user" DBUS_SESSION_BUS_ADDRESS="$dbus_addr" gnome-extensions "$action" "$extension_id" 2>/dev/null; then
        log "  [ok] $extension_id → ${action}d"
    else
        warn "Failed to $action $extension_id"
    fi
}

# --- Detect current power source ---------------------------------------------
detect_power_source() {
    if [[ -f "$AC_SUPPLY" ]]; then
        local ac_online
        ac_online=$(cat "$AC_SUPPLY" 2>/dev/null)
        if [[ "$ac_online" == "1" ]]; then
            echo "ac"
        else
            echo "battery"
        fi
    else
        warn "Cannot detect power source at $AC_SUPPLY"
        echo "unknown"
    fi
}

# --- Status command -----------------------------------------------------------
show_status() {
    echo "============================================================"
    echo "  Zephyrus G16 Power Status"
    echo "============================================================"
    echo ""

    # Power source
    local source
    source=$(detect_power_source)
    echo "Power source    : $source"

    # Battery info
    if [[ -f /sys/class/power_supply/BAT1/capacity ]]; then
        local cap
        cap=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
        local status
        status=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null)
        echo "Battery         : ${cap}% ($status)"
    fi

    # Current power draw
    if [[ -f /sys/class/power_supply/BAT1/power_now ]]; then
        local power_uw
        power_uw=$(cat /sys/class/power_supply/BAT1/power_now 2>/dev/null)
        if [[ -n "$power_uw" && "$power_uw" -gt 0 ]] 2>/dev/null; then
            local power_mw=$((power_uw / 1000))
            local power_w=$((power_mw / 1000))
            local power_frac=$(( (power_mw % 1000) / 10 ))
            printf "Power draw      : %d.%02dW\n" "$power_w" "$power_frac"
        fi
    elif [[ -f /sys/class/power_supply/BAT1/current_now ]]; then
        local curr
        curr=$(cat /sys/class/power_supply/BAT1/current_now 2>/dev/null)
        local volt
        volt=$(cat /sys/class/power_supply/BAT1/voltage_now 2>/dev/null)
        if [[ -n "$curr" && -n "$volt" ]]; then
            # P = V * I; both in µ-units → result in pW, convert to mW
            local power_mw=$(( (curr / 1000) * (volt / 1000) / 1000 ))
            local power_w=$((power_mw / 1000))
            local power_frac=$(( (power_mw % 1000) / 10 ))
            printf "Power draw      : ~%d.%02dW (estimated)\n" "$power_w" "$power_frac"
        fi
    fi

    echo ""

    # CPU cores
    echo "--- CPU Cores ---"
    local online_count=0
    local offline_count=0
    local online_list=""
    local offline_list=""
    for i in $(seq 0 15); do
        local path="/sys/devices/system/cpu/cpu${i}/online"
        if [[ "$i" -eq 0 ]] || { [[ -f "$path" ]] && [[ "$(cat "$path" 2>/dev/null)" == "1" ]]; }; then
            online_count=$((online_count + 1))
            online_list+="$i "
        else
            offline_count=$((offline_count + 1))
            offline_list+="$i "
        fi
    done
    echo "Online ($online_count)  : cpu{$online_list}"
    echo "Offline ($offline_count) : ${offline_list:-(none)}"

    # Turbo
    local turbo
    turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
    echo "Turbo boost     : $( [[ "$turbo" == "0" ]] && echo "enabled" || echo "DISABLED" )"

    # HWP dynamic boost
    local hwp
    hwp=$(cat /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost 2>/dev/null)
    echo "HWP dyn. boost  : $( [[ "$hwp" == "1" ]] && echo "enabled" || echo "disabled" )"

    # EPP
    local epp
    epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
    echo "EPP (cpu0)      : $epp"

    # Platform profile
    local profile
    profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)
    echo "Platform profile: $profile"

    # min_perf_pct
    local min_perf
    min_perf=$(cat /sys/devices/system/cpu/intel_pstate/min_perf_pct 2>/dev/null)
    echo "min_perf_pct    : ${min_perf}%"

    # RAPL
    local pl1
    pl1=$(cat "$RAPL_PL1" 2>/dev/null)
    local pl2
    pl2=$(cat "$RAPL_PL2" 2>/dev/null)
    if [[ -n "$pl1" ]]; then
        echo "RAPL PL1 (sust) : $((pl1 / 1000000))W"
    fi
    if [[ -n "$pl2" ]]; then
        echo "RAPL PL2 (burst): $((pl2 / 1000000))W"
    fi

    echo ""

    # GPU
    echo "--- GPU ---"
    local gpu_mode
    gpu_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
    echo "supergfxctl     : $gpu_mode"

    # dGPU runtime status (may not exist in integrated mode)
    if [[ -f /sys/bus/pci/devices/0000:01:00.0/power/runtime_status ]]; then
        local dgpu_status
        dgpu_status=$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null)
        echo "dGPU runtime    : $dgpu_status"
    else
        echo "dGPU runtime    : (PCI device not present — fully off)"
    fi

    echo ""

    # Power tunables
    echo "--- Tunables ---"
    local aspm
    aspm=$(cat /sys/module/pcie_aspm/parameters/policy 2>/dev/null)
    echo "PCIe ASPM       : $aspm"

    local audio_ps
    audio_ps=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null)
    echo "Audio power-save: ${audio_ps}s"

    local nmi
    nmi=$(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null)
    echo "NMI watchdog    : $nmi"

    local writeback
    writeback=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null)
    echo "VM writeback    : ${writeback}cs"

    local wifi_ps
    wifi_ps=$(iw dev "$WIFI_IFACE" get power_save 2>/dev/null | awk '{print $NF}')
    echo "WiFi power-save : $wifi_ps"

    echo ""

    # Temps
    echo "--- Temperatures ---"
    local pkg_temp
    pkg_temp=$(cat /sys/class/thermal/thermal_zone5/temp 2>/dev/null)
    if [[ -n "$pkg_temp" ]]; then
        printf "CPU package     : %d.%d°C\n" "$((pkg_temp / 1000))" "$(( (pkg_temp % 1000) / 100 ))"
    fi
    local acpi_temp
    acpi_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    if [[ -n "$acpi_temp" ]]; then
        printf "ACPI zone 0     : %d.%d°C\n" "$((acpi_temp / 1000))" "$(( (acpi_temp % 1000) / 100 ))"
    fi

    echo ""

    # Fan RPM
    local cpu_fan
    cpu_fan=$(cat /sys/class/hwmon/hwmon*/fan1_input 2>/dev/null | head -1)
    local gpu_fan
    gpu_fan=$(cat /sys/class/hwmon/hwmon*/fan2_input 2>/dev/null | head -1)
    echo "--- Fans ---"
    echo "CPU fan         : ${cpu_fan:-?} RPM"
    echo "GPU fan         : ${gpu_fan:-?} RPM"

    echo ""
    echo "============================================================"
}

# --- Battery Mode -------------------------------------------------------------
apply_battery() {
    log "=== Applying BATTERY mode ==="
    log ""

    # 1. CPU cores - keep all online, let Thread Director manage
    log "--- CPU cores ---"
    log "  [info] All 16 cores stay online (Thread Director manages efficiency)"

    log ""

    # RAPL power capping DISABLED — causes lags with Brave + Cursor at 15W+
    # sysfs_write "$RAPL_PL1" "$RAPL_PL1_BATTERY" "PL1 (sustained) → $((RAPL_PL1_BATTERY / 1000000))W"
    # sysfs_write "$RAPL_PL2" "$RAPL_PL2_BATTERY" "PL2 (burst) → $((RAPL_PL2_BATTERY / 1000000))W"

    log ""

    # 4. Disable turbo boost
    log "--- CPU power settings ---"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/no_turbo" "1" "Turbo boost → disabled"

    # 5. Disable HWP dynamic boost
    sysfs_write "/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost" "0" "HWP dynamic boost → disabled"

    # 6. Set min_perf_pct low
    sysfs_write "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "8" "min_perf_pct → 8%"

    # 7. Set EPP to power on all online cores
    set_epp_all "power"

    log ""

    # 7. Kernel tunables
    log "--- Kernel tunables ---"
    sysfs_write "/proc/sys/kernel/nmi_watchdog" "0" "NMI watchdog → off"
    sysfs_write "/proc/sys/vm/dirty_writeback_centisecs" "1500" "VM writeback → 1500cs"

    log ""

    # 8. PCIe ASPM — try to set powersupersave (may be locked at boot)
    log "--- PCIe ASPM ---"
    local aspm_policy="/sys/module/pcie_aspm/parameters/policy"
    if [[ -w "$aspm_policy" ]]; then
        sysfs_write "$aspm_policy" "powersupersave" "PCIe ASPM → powersupersave"
    else
        log "  [skip] PCIe ASPM: read-only (set via kernel cmdline pcie_aspm.policy=powersupersave)"
    fi

    # 9. PCI Runtime PM — set all devices to "auto" EXCEPT GPU (D3cold wake protection)
    log "--- PCI Runtime PM → auto (excluding GPU) ---"
    for pci_ctrl in /sys/bus/pci/devices/*/power/control; do
        local pci_addr
        pci_addr=$(echo "$pci_ctrl" | grep -oP '0000:[0-9a-f:.]+')
        # Skip GPU slot to prevent D3cold wake issues with nvidia-open driver
        if [[ "$pci_addr" == "0000:01:00.0" ]]; then
            sysfs_write "$pci_ctrl" "on" "  PCI $pci_addr (GPU) runtime PM → on (D3cold protection)"
        else
            sysfs_write "$pci_ctrl" "auto" "  PCI $pci_addr runtime PM"
        fi
    done

    log ""

    # 10. Audio power-save (60 second timeout) + codec PM
    log "--- Audio ---"
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save" "60" "Audio power-save → 60s"
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save_controller" "Y" "Audio codec PM → enabled"

    log ""

    # 10. USB selective autosuspend (2 second timeout, skip HID)
    usb_autosuspend 2

    log ""

    # 11. WiFi power-save
    log "--- WiFi ---"
    if $DRY_RUN; then
        log "  [dry-run] WiFi power_save → on"
    else
        if iw dev "$WIFI_IFACE" set power_save on 2>/dev/null; then
            log "  [ok] WiFi power_save → on"
        else
            warn "Failed to set WiFi power_save"
        fi
    fi

    log ""

    # 12. Bluetooth — power off to save battery
    log "--- Bluetooth ---"
    if command -v bluetoothctl &>/dev/null; then
        if $DRY_RUN; then
            log "  [dry-run] Bluetooth → power off"
        else
            if bluetoothctl power off &>/dev/null; then
                log "  [ok] Bluetooth → power off"
            else
                warn "Failed to power off Bluetooth (may already be off)"
            fi
        fi
    else
        log "  [skip] bluetoothctl not found"
    fi

    log ""

    # 14. Display refresh rate — 60Hz for battery savings (OLED)
    log "--- Display ---"
    set_refresh_rate 60

    log ""

    # 15. GNOME extensions — disable heavy extensions on battery
    log "--- GNOME Extensions ---"
    toggle_gnome_extension "blur-my-shell@aunetx" "disable"

    log ""

    # 16. GPU — switch to Integrated mode for battery savings
    log "--- GPU ---"
    if command -v supergfxctl &>/dev/null; then
        local gpu_mode
        gpu_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
        log "  [info] GPU mode: $gpu_mode"
        log "  [info] GPU mode changes require logout - not switching automatically"
        log "  [info] To switch manually: supergfxctl -m Integrated"
    else
        log "  [skip] supergfxctl not found"
    fi

    log ""
    log "=== Battery mode applied ==="
    log "All 16 cores online with RAPL 8W cap, EPP=power, turbo off"
    log "Run '$0 status' to verify current state"
}

# --- AC / Beast Mode ----------------------------------------------------------
apply_ac() {
    log "=== Applying AC / BEAST mode ==="
    log ""

    # 1. Bring ALL cores back online (do this FIRST)
    log "--- Onlining all cores ---"
    for cpu in $(seq 1 15); do
        cpu_set_online "$cpu" 1
    done

    log ""

    # 2. RAPL power cap — restore full power
    log "--- RAPL power limits ---"
    sysfs_write "$RAPL_PL1" "$RAPL_PL1_AC" "PL1 (sustained) → $((RAPL_PL1_AC / 1000000))W"
    sysfs_write "$RAPL_PL2" "$RAPL_PL2_AC" "PL2 (burst) → $((RAPL_PL2_AC / 1000000))W"

    log ""

    # 3. Enable turbo boost
    log "--- CPU power settings ---"
    sysfs_write "/sys/devices/system/cpu/intel_pstate/no_turbo" "0" "Turbo boost → enabled"

    # 4. Enable HWP dynamic boost
    sysfs_write "/sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost" "1" "HWP dynamic boost → enabled"

    # 5. Raise min_perf_pct
    sysfs_write "/sys/devices/system/cpu/intel_pstate/min_perf_pct" "30" "min_perf_pct → 30%"

    # 6. Set EPP to performance on all cores
    set_epp_all "performance"

    log ""

    # 7. Platform profile — ensure performance mode
    log "--- Platform profile ---"
    sysfs_write "/sys/firmware/acpi/platform_profile" "performance" "Platform profile → performance"

    log ""

    # 8. Kernel tunables
    log "--- Kernel tunables ---"
    sysfs_write "/proc/sys/kernel/nmi_watchdog" "1" "NMI watchdog → on"
    sysfs_write "/proc/sys/vm/dirty_writeback_centisecs" "500" "VM writeback → 500cs"

    log ""

    # 9. NVMe I/O scheduler — 'none' for lowest latency on fast storage
    log "--- NVMe scheduler ---"
    for nvme_sched in /sys/block/nvme*/queue/scheduler; do
        local nvme_dev
        nvme_dev=$(echo "$nvme_sched" | grep -oP 'nvme[0-9]+')
        sysfs_write "$nvme_sched" "none" "  $nvme_dev scheduler → none"
    done

    log ""

    # 10. PCIe ASPM — try to set default (may be locked at boot)
    log "--- PCIe ASPM ---"
    local aspm_policy="/sys/module/pcie_aspm/parameters/policy"
    if [[ -w "$aspm_policy" ]]; then
        sysfs_write "$aspm_policy" "default" "PCIe ASPM → default"
    else
        log "  [skip] PCIe ASPM: read-only (set via kernel cmdline)"
    fi

    # 8. PCI Runtime PM — set all devices to "on" (always active, lowest latency)
    log "--- PCI Runtime PM → on ---"
    for pci_ctrl in /sys/bus/pci/devices/*/power/control; do
        local pci_addr
        pci_addr=$(echo "$pci_ctrl" | grep -oP '0000:[0-9a-f:.]+')
        sysfs_write "$pci_ctrl" "on" "  PCI $pci_addr runtime PM"
    done

    log ""

    # 9. Audio power-save off
    log "--- Audio ---"
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save" "0" "Audio power-save → off"
    sysfs_write "/sys/module/snd_hda_intel/parameters/power_save_controller" "N" "Audio codec PM → disabled"

    log ""

    # 9. USB autosuspend off
    usb_autosuspend -1

    log ""

    # 10. WiFi power-save off
    log "--- WiFi ---"
    if $DRY_RUN; then
        log "  [dry-run] WiFi power_save → off"
    else
        if iw dev "$WIFI_IFACE" set power_save off 2>/dev/null; then
            log "  [ok] WiFi power_save → off"
        else
            warn "Failed to unset WiFi power_save"
        fi
    fi

    log ""

    # 11. Bluetooth — power on for full functionality
    log "--- Bluetooth ---"
    if command -v bluetoothctl &>/dev/null; then
        if $DRY_RUN; then
            log "  [dry-run] Bluetooth → power on"
        else
            if bluetoothctl power on &>/dev/null; then
                log "  [ok] Bluetooth → power on"
            else
                warn "Failed to power on Bluetooth"
            fi
        fi
    else
        log "  [skip] bluetoothctl not found"
    fi

    log ""

    # 13. Display refresh rate — native high refresh for performance
    log "--- Display ---"
    set_refresh_rate 240

    log ""

    # 14. GNOME extensions — enable visual effects on AC
    log "--- GNOME Extensions ---"
    toggle_gnome_extension "blur-my-shell@aunetx" "enable"

    log ""

    # 15. GPU — don't auto-switch, too risky during active session
    log "--- GPU ---"
    if command -v supergfxctl &>/dev/null; then
        local gpu_mode
        gpu_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
        log "  [info] GPU mode: $gpu_mode"
        log "  [info] GPU mode changes require logout - not switching automatically"
        log "  [info] To switch manually: supergfxctl -m Hybrid"
        
        # Still do PCI rescan if dGPU is expected but missing
        if [[ "$gpu_mode" == "Hybrid" ]] && [[ ! -d /sys/bus/pci/devices/0000:01:00.0 ]]; then
            log "  dGPU not on PCI bus, rescanning..."
            if $DRY_RUN; then
                log "  [dry-run] Would rescan PCI bus"
            else
                echo 1 > /sys/bus/pci/rescan 2>/dev/null
                sleep 1
                if [[ -d /sys/bus/pci/devices/0000:01:00.0 ]]; then
                    log "  [ok] dGPU woke up from D3cold"
                else
                    warn "dGPU still not visible after PCI rescan"
                fi
            fi
        fi
    else
        log "  [skip] supergfxctl not found"
    fi

    log ""
    log "=== AC / Beast mode applied ==="
    log "All 16 cores online, turbo + HWP boost enabled, EPP=performance"
    log "Run '$0 status' to verify current state"
}

# --- Main ---------------------------------------------------------------------
main() {
    local mode="${1:-}"
    local flag="${2:-}"

    if [[ "$flag" == "--dry-run" ]]; then
        DRY_RUN=true
        log "(DRY RUN — no changes will be applied)"
        log ""
    fi

    case "$mode" in
        battery)
            if [[ "$EUID" -ne 0 ]] && ! $DRY_RUN; then
                echo "Error: 'battery' mode requires root. Use: sudo $0 battery" >&2
                exit 1
            fi
            apply_battery
            ;;
        ac)
            if [[ "$EUID" -ne 0 ]] && ! $DRY_RUN; then
                echo "Error: 'ac' mode requires root. Use: sudo $0 ac" >&2
                exit 1
            fi
            apply_ac
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {battery|ac|status} [--dry-run]"
            echo ""
            echo "Commands:"
            echo "  battery          Apply battery-saving optimizations (requires root)"
            echo "  ac               Apply full-performance AC mode (requires root)"
            echo "  status           Show current power state (no root needed)"
            echo ""
            echo "Flags:"
            echo "  --dry-run        Preview changes without applying them"
            exit 1
            ;;
    esac
}

main "$@"
