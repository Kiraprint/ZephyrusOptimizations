#!/usr/bin/env bash
# =============================================================================
# test-all.sh — Run all module tests (status checks)
#
# Usage:
#   ./test-all.sh              # Status of all modules
#   ./test-all.sh battery      # Dry-run battery mode on all modules
#   ./test-all.sh ac           # Dry-run AC mode on all modules
#   sudo ./test-all.sh apply-battery  # Actually apply battery mode
#   sudo ./test-all.sh apply-ac       # Actually apply AC mode
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODULES=(
    "cpu-cores"
    "cpu-power"
    "pci-power"
    "kernel-tunables"
    "audio"
    "usb"
    "network"
    "display"
    "gpu"
    "platform"
)

run_module() {
    local module="$1"
    local action="$2"
    local flags="${3:-}"
    
    local script="$SCRIPT_DIR/${module}.sh"
    
    if [[ ! -x "$script" ]]; then
        echo "WARNING: $script not found or not executable"
        return 1
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Module: $module"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    "$script" "$action" $flags
}

show_all_status() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║         Zephyrus G16 Power Optimization Status           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    
    for module in "${MODULES[@]}"; do
        run_module "$module" "status"
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Status check complete"
}

dry_run_mode() {
    local mode="$1"
    
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║      Dry-run: $mode mode (no changes applied)            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    
    for module in "${MODULES[@]}"; do
        run_module "$module" "$mode" "--dry-run"
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Dry-run complete — no changes were made"
}

apply_mode() {
    local mode="$1"
    
    if [[ "$EUID" -ne 0 ]]; then
        echo "Error: apply-$mode requires root. Use: sudo $0 apply-$mode" >&2
        exit 1
    fi
    
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║        Applying: $mode mode                              ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    
    for module in "${MODULES[@]}"; do
        run_module "$module" "$mode"
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$mode mode applied to all modules"
}

case "${1:-status}" in
    status)
        show_all_status
        ;;
    battery)
        dry_run_mode "battery"
        ;;
    ac)
        dry_run_mode "ac"
        ;;
    apply-battery)
        apply_mode "battery"
        ;;
    apply-ac)
        apply_mode "ac"
        ;;
    *)
        echo "Usage: $0 {status|battery|ac|apply-battery|apply-ac}"
        echo ""
        echo "Commands:"
        echo "  status         Show current state of all optimizations"
        echo "  battery        Dry-run battery mode on all modules"
        echo "  ac             Dry-run AC mode on all modules"
        echo "  apply-battery  Apply battery mode (requires root)"
        echo "  apply-ac       Apply AC mode (requires root)"
        echo ""
        echo "Individual module testing:"
        echo "  ./cpu-cores.sh status"
        echo "  sudo ./cpu-power.sh battery --dry-run"
        echo "  etc."
        exit 1
        ;;
esac
