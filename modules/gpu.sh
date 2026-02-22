#!/usr/bin/env bash
# =============================================================================
# gpu.sh — GPU mode verification (supergfxctl)
#
# Test independently:
#   ./gpu.sh status
#   ./gpu.sh battery   # Just verifies, doesn't change mode
#   ./gpu.sh ac
#
# NOTE: This module does NOT auto-switch GPU modes because:
#   1. Switching requires logout/login
#   2. Integrated mode triggers D3cold wake bugs on GU605CX
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
LOG_PREFIX="[gpu]"

GPU_PCI_ADDR="0000:01:00.0"

show_status() {
    echo "=== GPU Status ==="
    
    # supergfxctl mode
    local gpu_mode
    gpu_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
    echo "supergfxctl mode: $gpu_mode"
    
    # dGPU runtime status
    if [[ -f "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_status" ]]; then
        local dgpu_status
        dgpu_status=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_status" 2>/dev/null)
        echo "dGPU runtime    : $dgpu_status"
        
        local dgpu_control
        dgpu_control=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/control" 2>/dev/null)
        echo "dGPU PM control : $dgpu_control"
        
        # Suspended time
        local suspended_time
        suspended_time=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_suspended_time" 2>/dev/null)
        local active_time
        active_time=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_active_time" 2>/dev/null)
        if [[ -n "$suspended_time" && -n "$active_time" ]]; then
            echo "Suspended time  : $((suspended_time / 1000))s"
            echo "Active time     : $((active_time / 1000))s"
        fi
    else
        echo "dGPU runtime    : (PCI device not present — fully powered off)"
    fi
    
    # nvidia-smi if available
    if command -v nvidia-smi &>/dev/null; then
        echo ""
        echo "nvidia-smi:"
        nvidia-smi --query-gpu=name,power.draw,temperature.gpu,utilization.gpu --format=csv,noheader 2>/dev/null || echo "  (GPU not accessible)"
    fi
}

check_battery() {
    log "=== GPU Battery Mode Check ==="
    
    local gpu_mode
    gpu_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
    
    # Hybrid mode is CORRECT for GU605CX — Integrated mode causes D3cold wake bugs
    if [[ "$gpu_mode" == "Hybrid" ]]; then
        local dgpu_status
        dgpu_status=$(cat "/sys/bus/pci/devices/$GPU_PCI_ADDR/power/runtime_status" 2>/dev/null || echo "unknown")
        
        if [[ "$dgpu_status" == "suspended" ]]; then
            log "  [ok] GPU mode: Hybrid, dGPU suspended (correct for this hardware)"
        else
            warn "GPU is Hybrid but dGPU runtime_status='$dgpu_status' (expected: suspended)"
            warn "dGPU may be drawing power — check for running GPU processes:"
            warn "  nvidia-smi pmon -c 1"
        fi
    elif [[ "$gpu_mode" == "Integrated" ]]; then
        warn "GPU is in Integrated mode — this can cause D3cold wake bugs on GU605CX!"
        warn "Recommended: Keep in Hybrid mode"
        warn "  supergfxctl --mode Hybrid  (requires logout/login)"
    else
        log "  [info] GPU mode: $gpu_mode"
    fi
    
    log ""
    log "NOTE: GPU mode not changed automatically (requires logout/login)"
}

check_ac() {
    log "=== GPU AC Mode Check ==="
    
    local gpu_mode
    gpu_mode=$(supergfxctl --get 2>/dev/null || echo "unknown")
    
    if [[ "$gpu_mode" == "Hybrid" ]]; then
        log "  [ok] GPU mode: Hybrid (dGPU available for CUDA/games)"
    else
        log "  [info] GPU is in '$gpu_mode' mode."
        log "  [info] For full GPU power, run: supergfxctl --mode Hybrid"
        log "  [info] (Requires logout/login)"
    fi
    
    log ""
    log "NOTE: GPU mode not changed automatically (requires logout/login)"
}

main() {
    local mode
    mode=$(parse_module_args "$@")
    
    case "$mode" in
        battery)  check_battery ;;
        ac)       check_ac ;;
        status)   show_status ;;
        *)
            echo "Usage: $0 {battery|ac|status}"
            echo ""
            echo "  battery    Verify GPU mode for battery (Hybrid + suspended)"
            echo "  ac         Verify GPU mode for AC (Hybrid)"
            echo "  status     Show detailed GPU status"
            echo ""
            echo "NOTE: This module does NOT change GPU mode automatically."
            echo "      Integrated mode is broken on GU605CX (D3cold wake bug)."
            echo "      Keep in Hybrid mode — dGPU suspends automatically."
            exit 1
            ;;
    esac
}

main "$@"
