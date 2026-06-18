#!/usr/bin/env bash
# =============================================================================
# force-dgpu-sleep.sh — Force dGPU into D3cold by restarting processes
#
# This script:
# 1. Checks if dGPU is doing actual GPU work
# 2. If not, identifies KDE services with NVIDIA libraries loaded
# 3. Restarts safe KDE services to unload libraries
# 4. Allows dGPU to enter D3cold sleep state
#
# SAFETY: Only restarts system daemons, NOT user applications
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../core/common.sh"
LOG_PREFIX="[force-dgpu-sleep]"

GPU_PCI_ADDR="0000:01:00.0"

# Safe services that can be restarted without user impact
SAFE_RESTART_SERVICES=(
    "dbus-:1.2-org.kde.kwalletd6@1.service"  # KWallet
    "plasma-kded6.service"                    # KDE Daemon
)

# Processes that need killing (will auto-restart via D-Bus activation)
SAFE_KILL_PROCESSES=(
    "ksecretd"      # KDE Secrets Daemon (PAM-launched, will restart on demand)
    "kded6"         # KDE Daemon (systemd will restart)
)

check_dgpu_active_work() {
    # Check if dGPU is doing actual GPU work (not just loaded libs)
    if ! command -v nvidia-smi &>/dev/null; then
        echo "nvidia-smi not found"
        return 1
    fi
    
    # Check GPU utilization
    local gpu_util
    gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    
    if [[ -z "$gpu_util" ]]; then
        echo "Cannot query GPU"
        return 1
    fi
    
    # If GPU utilization > 5%, consider it actively working
    if [[ "$gpu_util" -gt 5 ]]; then
        echo "GPU is actively working (${gpu_util}% utilization)"
        return 0
    fi
    
    # Check if any process is using GPU for compute/graphics
    local active_procs
    active_procs=$(nvidia-smi pmon -c 1 2>/dev/null | grep -v "^#" | grep -v "^\s*$" | grep -v " - " | wc -l)
    
    if [[ "$active_procs" -gt 0 ]]; then
        echo "GPU has active processes"
        return 0
    fi
    
    echo "GPU is idle"
    return 1
}

find_nvidia_processes() {
    # Find processes with NVIDIA libraries or devices open
    echo "Processes with NVIDIA access:"
    echo ""
    
    # Check /dev/nvidia* users
    echo "Device users:"
    fuser -v /dev/nvidia* 2>&1 | grep -v "USER" | awk '{print $2, $4}' | sort -u
    
    echo ""
    echo "Library users:"
    # Check processes with nvidia libraries loaded
    lsof 2>/dev/null | grep "libnvidia" | awk '{print $1}' | sort | uniq -c | sort -rn
}

get_safe_to_restart() {
    local restart_list=""
    
    # Check which safe processes have nvidia libs loaded
    for proc in "${SAFE_KILL_PROCESSES[@]}"; do
        if pgrep -x "$proc" >/dev/null; then
            # Check if this process has nvidia libs
            local pids
            pids=$(pgrep -x "$proc")
            for pid in $pids; do
                if lsof -p "$pid" 2>/dev/null | grep -q "libnvidia"; then
                    restart_list="$restart_list $proc"
                    break
                fi
            done
        fi
    done
    
    echo "$restart_list"
}

restart_kde_services() {
    log "=== Restarting KDE services to unload NVIDIA libraries ==="
    
    local display_user
    display_user=$(detect_display_user)
    
    if [[ -z "$display_user" ]]; then
        warn "Cannot detect display user"
        return 1
    fi
    
    local restarted=0
    
    # Restart systemd services
    for service in "${SAFE_RESTART_SERVICES[@]}"; do
        if run_as_display_user "$display_user" systemctl --user is-active "$service" &>/dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  [dry-run] Would restart: $service"
            else
                log "  Restarting: $service"
                run_as_display_user "$display_user" systemctl --user restart "$service" &
                restarted=1
            fi
        fi
    done
    
    # Kill safe processes (they will auto-restart on demand)
    local procs_to_restart
    procs_to_restart=$(get_safe_to_restart)
    
    if [[ -n "$procs_to_restart" ]]; then
        for proc in $procs_to_restart; do
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  [dry-run] Would kill: $proc (auto-restarts on demand)"
            else
                log "  Killing: $proc (will auto-restart)"
                pkill -x "$proc"
                restarted=1
            fi
        done
    fi
    
    if [[ "$restarted" -eq 0 ]]; then
        log "  [info] No services need restarting"
    else
        # Wait for services to restart
        if [[ "$DRY_RUN" != "true" ]]; then
            sleep 2
        fi
    fi
    
    log ""
    log "KDE services restarted"
}

check_dgpu_runtime_status() {
    if [[ ! -f "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_status" ]]; then
        echo "unknown"
        return
    fi
    
    cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_status" 2>/dev/null
}

show_status() {
    echo "=== dGPU Runtime Status ==="
    echo ""
    
    local runtime_status
    runtime_status=$(check_dgpu_runtime_status)
    echo "dGPU runtime state: $runtime_status"
    
    if [[ "$runtime_status" == "active" ]]; then
        echo "  ⚠️  dGPU is active (consuming power)"
    elif [[ "$runtime_status" == "suspended" ]]; then
        echo "  ✓ dGPU is suspended (D3cold sleep)"
    fi
    
    echo ""
    
    # Check if GPU is doing work
    if command -v nvidia-smi &>/dev/null; then
        local gpu_util
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        local gpu_power
        gpu_power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
        
        echo "GPU utilization: ${gpu_util}%"
        echo "GPU power draw : ${gpu_power}W"
        echo ""
    fi
    
    find_nvidia_processes
}

force_sleep() {
    log "=== Forcing dGPU into D3cold sleep ==="
    log ""
    
    # Check runtime status
    local runtime_status
    runtime_status=$(check_dgpu_runtime_status)
    
    if [[ "$runtime_status" == "suspended" ]]; then
        log "  [ok] dGPU is already suspended (D3cold)"
        return 0
    fi
    
    log "Current dGPU state: $runtime_status"
    log ""
    
    # Check if GPU is actively working
    if check_dgpu_active_work >/dev/null 2>&1; then
        warn "dGPU is actively being used for GPU work"
        warn "Cannot force sleep while GPU is working"
        warn ""
        warn "Active processes:"
        nvidia-smi pmon -c 1 2>&1 | grep -v "^#" | grep -v " - "
        return 1
    fi
    
    log "dGPU is idle but runtime-active (libraries loaded)"
    log ""
    
    # Find which processes need restarting
    log "Analyzing processes with NVIDIA libraries..."
    local procs_to_restart
    procs_to_restart=$(get_safe_to_restart)
    
    if [[ -n "$procs_to_restart" ]]; then
        log "  Found KDE services with NVIDIA libs: $procs_to_restart"
    else
        log "  No safe-to-restart services found with NVIDIA libs"
    fi
    
    # Check for user apps (unsafe to restart)
    local unsafe_apps
    unsafe_apps=$(lsof 2>/dev/null | grep "libnvidia" | awk '{print $1}' | sort -u | grep -vE "^(ksecretd|kded6|kwalletd6|plasma|xdg-desktop)$")
    
    if [[ -n "$unsafe_apps" ]]; then
        warn ""
        warn "User applications with NVIDIA libraries loaded:"
        echo "$unsafe_apps" | sed 's/^/    /'
        warn ""
        warn "These will keep dGPU active. Consider closing them for full power savings."
    fi
    
    log ""
    
    # Restart KDE services
    restart_kde_services
    
    # Check if it worked
    sleep 3
    runtime_status=$(check_dgpu_runtime_status)
    
    if [[ "$runtime_status" == "suspended" ]]; then
        log ""
        log "✓ Success! dGPU entered D3cold sleep state"
    elif [[ "$runtime_status" == "active" ]]; then
        warn ""
        warn "dGPU is still active"
        warn "Remaining processes may still have NVIDIA access:"
        find_nvidia_processes | grep -v "^$"
    else
        log ""
        log "dGPU state: $runtime_status"
    fi
}

main() {
    local mode=""
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            force|battery|status)
                mode="$arg"
                ;;
            --dry-run)
                DRY_RUN="true"
                export DRY_RUN
                ;;
        esac
    done
    
    if [[ -z "$mode" ]]; then
        echo "Usage: $0 {force|status} [--dry-run]"
        echo ""
        echo "  force      Force dGPU into D3cold by restarting KDE services"
        echo "  status     Show dGPU runtime status and processes using it"
        echo ""
        echo "SAFETY: Only restarts system daemons (ksecretd, kded6, kwalletd6)"
        echo "        User applications (Brave, Electron) are NOT restarted"
        echo ""
        echo "This is a runtime workaround. For permanent solution, use:"
        echo "  compositor-gpu.sh battery  # Requires logout"
        exit 1
    fi
    
    case "$mode" in
        battery|force)
            force_sleep
            ;;
        status)
            show_status
            ;;
    esac
}

main "$@"
