#!/usr/bin/env bash
# =============================================================================
# test-cpu-offline.sh — Test if CPU core offlining actually works
#
# Run with: sudo ./test-cpu-offline.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_info() { echo "[INFO] $*"; }

# Check root
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: Must run as root. Use: sudo $0"
    exit 1
fi

echo "============================================================"
echo "  CPU Core Offline Test - CachyOS / Arrow Lake"
echo "============================================================"
echo ""

# Test CPU to offline (use cpu5 - a P-core that's not cpu0)
TEST_CPU=5
ONLINE_PATH="/sys/devices/system/cpu/cpu${TEST_CPU}/online"

# --- Pre-flight checks ---
echo "=== Pre-flight Checks ==="

# Check if online file exists
if [[ ! -f "$ONLINE_PATH" ]]; then
    log_fail "CPU${TEST_CPU} online file not found at $ONLINE_PATH"
    exit 1
fi
log_ok "Online sysfs file exists: $ONLINE_PATH"

# Check if writable
if [[ -w "$ONLINE_PATH" ]]; then
    log_ok "Online file is writable"
else
    log_fail "Online file is NOT writable"
    log_info "This may indicate kernel CONFIG_HOTPLUG_CPU is disabled"
    exit 1
fi

# Check kernel config
echo ""
echo "=== Kernel Configuration ==="
if [[ -f /proc/config.gz ]]; then
    HOTPLUG_CONFIG=$(zcat /proc/config.gz 2>/dev/null | grep "^CONFIG_HOTPLUG_CPU=" || echo "")
    if [[ "$HOTPLUG_CONFIG" == "CONFIG_HOTPLUG_CPU=y" ]]; then
        log_ok "CONFIG_HOTPLUG_CPU=y (CPU hotplug enabled in kernel)"
    else
        log_fail "CONFIG_HOTPLUG_CPU not enabled (got: '$HOTPLUG_CONFIG')"
        exit 1
    fi
else
    log_warn "/proc/config.gz not available, skipping kernel config check"
fi

# Check for any kernel restrictions
echo ""
echo "=== Kernel Command Line ==="
CMDLINE=$(cat /proc/cmdline)
if echo "$CMDLINE" | grep -qE "nosmp|maxcpus=1|nr_cpus=1"; then
    log_fail "Kernel has CPU restrictions in cmdline: $CMDLINE"
    exit 1
fi
log_ok "No CPU restrictions in kernel cmdline"

# --- Actual Test ---
echo ""
echo "=== Testing CPU${TEST_CPU} Offline/Online ==="

# Get initial state
INITIAL_ONLINE=$(cat "$ONLINE_PATH")
INITIAL_CPU_COUNT=$(grep -c processor /proc/cpuinfo)

log_info "Initial state: cpu${TEST_CPU} online=$INITIAL_ONLINE, total CPUs=$INITIAL_CPU_COUNT"

# Step 1: Try to offline
echo ""
echo "--- Step 1: Offlining cpu${TEST_CPU} ---"

if echo 0 > "$ONLINE_PATH" 2>/dev/null; then
    sleep 0.5
    NEW_STATE=$(cat "$ONLINE_PATH")
    NEW_CPU_COUNT=$(grep -c processor /proc/cpuinfo)
    
    if [[ "$NEW_STATE" == "0" ]]; then
        log_ok "cpu${TEST_CPU} successfully offlined!"
        log_info "State: online=$NEW_STATE, total CPUs=$NEW_CPU_COUNT (was $INITIAL_CPU_COUNT)"
        
        # Verify in /proc/cpuinfo
        if ! grep -q "^processor.*: ${TEST_CPU}$" /proc/cpuinfo 2>/dev/null; then
            log_ok "Confirmed: cpu${TEST_CPU} NOT in /proc/cpuinfo"
        else
            log_warn "cpu${TEST_CPU} still appears in /proc/cpuinfo (unexpected)"
        fi
        
        # Check dmesg for confirmation
        DMESG_MSG=$(dmesg | tail -20 | grep -i "cpu.*${TEST_CPU}" || echo "")
        if [[ -n "$DMESG_MSG" ]]; then
            log_info "dmesg shows: $DMESG_MSG"
        fi
        
        OFFLINE_WORKS=true
    else
        log_fail "Write succeeded but state didn't change (still $NEW_STATE)"
        OFFLINE_WORKS=false
    fi
else
    log_fail "Failed to write to $ONLINE_PATH"
    log_info "Error: $(cat "$ONLINE_PATH" 2>&1 || echo "unknown")"
    OFFLINE_WORKS=false
fi

# Step 2: Bring it back online
echo ""
echo "--- Step 2: Re-onlining cpu${TEST_CPU} ---"

if echo 1 > "$ONLINE_PATH" 2>/dev/null; then
    sleep 0.5
    RESTORED_STATE=$(cat "$ONLINE_PATH")
    RESTORED_CPU_COUNT=$(grep -c processor /proc/cpuinfo)
    
    if [[ "$RESTORED_STATE" == "1" ]]; then
        log_ok "cpu${TEST_CPU} successfully brought back online!"
        log_info "State: online=$RESTORED_STATE, total CPUs=$RESTORED_CPU_COUNT"
    else
        log_fail "Failed to bring cpu${TEST_CPU} back online"
    fi
else
    log_fail "Failed to write 1 to $ONLINE_PATH"
fi

# --- Summary ---
echo ""
echo "============================================================"
echo "  Summary"
echo "============================================================"

if [[ "$OFFLINE_WORKS" == "true" ]]; then
    echo -e "${GREEN}SUCCESS: CPU core offlining WORKS on your system!${NC}"
    echo ""
    echo "You can safely use the power-switch.sh battery mode to offline:"
    echo "  - P-cores: cpu1-5 (5 cores)"
    echo "  - E-cores: cpu10-13 (4 cores)"
    echo "  - Total: 9 cores offlined, 7 remain online"
    echo ""
    echo "Test with: sudo ./modules/cpu-cores.sh battery"
else
    echo -e "${RED}FAILED: CPU core offlining does NOT work${NC}"
    echo ""
    echo "Possible reasons:"
    echo "  1. Kernel compiled without CONFIG_HOTPLUG_CPU"
    echo "  2. Firmware/BIOS restriction"
    echo "  3. CachyOS-specific configuration"
    echo ""
    echo "Check with:"
    echo "  zcat /proc/config.gz | grep HOTPLUG_CPU"
    echo "  dmesg | grep -i hotplug"
fi
