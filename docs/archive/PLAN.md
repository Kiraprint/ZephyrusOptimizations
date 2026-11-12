# Zephyrus G16 Battery Optimization Plan

## Target
- **On Battery**: 3–5W idle power draw
- **On AC (240W)**: Full unrestricted performance
- **All changes are conditional** — triggered by power source, never permanent

## Verified Hardware & Software (from live system)
```
Model     : ASUS ROG Zephyrus G16 (GU605CX)
CPU 0–5   : P-Cores  (Lion Cove)  — max 5400 MHz — 6 cores
CPU 6–13  : E-Cores  (Skymont)    — max 4500 MHz — 8 cores
CPU 14–15 : LP E-Cores            — max 2500 MHz — 2 cores
Driver    : intel_pstate (HWP mode)
no_turbo  : available at /sys/devices/system/cpu/intel_pstate/no_turbo
Display   : OLED 2560x1600 240Hz (VRR 48-240Hz, power-save range 48-60Hz)
dGPU      : NVIDIA RTX 5090 (supergfxctl: Hybrid only — Integrated mode broken, see Known Issues)

asusctl   : v6.3.2 (installed)
  Profiles: Quiet / Balanced / Performance
  Auto:     AC → Performance, Battery → Quiet  (ALREADY CONFIGURED)
  Battery:  charge limit 80%
  LEDs:     keyboard backlight off
  Fans:     custom curve (conservative: 0% until ~73°C)
```

## Architecture: Dual-Mode Switching
Everything hinges on detecting AC vs Battery and applying the right profile automatically.

### Switching Mechanism
`asusctl` already handles: profile (Quiet/Performance), fan curves, keyboard LEDs.
Our script layers the **extra** tweaks that `asusctl` doesn't cover.

- **Primary**: `udev` rule on power supply change → triggers `power-switch.sh`
- **asusctl**: Already auto-switches profiles (AC→Performance, Battery→Quiet)
- **Our script adds**: Core offlining (9 cores off on battery), turbo toggle, EPP, ASPM, USB, audio, HWP boost
- **PPD integration**: GNOME quick settings still work as an override

### On Battery (target ~4W idle)
**Core strategy**: All 16 cores stay online — Intel Thread Director + RAPL is more efficient than manual offlining.

Testing showed core offlining doesn't save power on Arrow Lake because:
1. Idle cores in deep C-states already consume near 0W
2. Fewer cores = scheduler overhead + higher per-core utilization
3. Thread Director optimally places tasks on efficient cores

| Layer              | Action                                                      |
|--------------------|-------------------------------------------------------------|
| **All Cores**      | Stay online (Thread Director manages efficiency)             |
| **RAPL PL1/PL2**   | Cap to 8W sustained / 20W burst (tested: 3W=laggy, 8W=usable)|
| **Turbo Boost**    | Disabled (`no_turbo=1`)                                      |
| **HWP Dynamic**    | Disabled (`hwp_dynamic_boost=0`)                             |
| **min_perf_pct**   | Set to 8% (deep idle allowed)                                |
| **CPU EPP**        | Set to `power` on all 7 online cores                         |
| **dGPU**           | Keep Hybrid mode (D3cold bug with Integrated), verify suspended |
| **Display**        | VRR 48-60Hz (auto-adapts to 48Hz when idle), true-black theme|
| **Keyboard BL**    | Off (already set via `asusctl`)                              |
| **Fan profile**    | Silent / Quiet (via `asusctl`) — EC should keep fans at 0    |
| **Bluetooth**      | Power off via `bluetoothctl`                                 |
| **WiFi**           | Power-save mode on                                           |
| **PCIe ASPM**      | Force `powersupersave` (if writable, else kernel cmdline)    |
| **PCI Runtime PM** | Set all devices to `auto` (except GPU slot → `on`)           |
| **USB**            | Selective autosuspend 2s (skip HID devices)                  |
| **Audio codec**    | Power-save timeout 60s + codec PM enabled                    |
| **NMI watchdog**   | Off                                                          |
| **VM writeback**   | Extended interval (1500cs)                                   |

**Power budget estimate:**
```
CPU (7 cores, EPP=power, no turbo) :  ~0.7–1.5W
OLED (dark theme, low brightness)  :  ~0.5–1.5W
NVMe (power-save)                  :  ~0.3–0.5W
WiFi (power-save)                  :  ~0.3–0.5W
RAM + chipset + misc               :  ~1.0–1.5W
────────────────────────────────────────────────
Estimated total                    :  ~3–5W
```

### On AC — Beast Mode (full 240W)
| Layer                | Action                                                          |
|----------------------|-----------------------------------------------------------------|
| **All Cores**        | CPUs 0–15 online                                                |
| **RAPL PL1/PL2**     | Restore to 110W / 110W (full power budget)                      |
| **Turbo Boost**      | Enabled (`no_turbo=0`)                                          |
| **HWP Dynamic Boost**| Enabled (`hwp_dynamic_boost=1`) — lets HW exceed standard turbo |
| **CPU EPP**          | Set to `performance` on all cores                               |
| **min_perf_pct**     | Raise to 30% (prevents deep idle dips during bursty workloads)  |
| **Platform Profile** | `performance` (via `/sys/firmware/acpi/platform_profile`)       |
| **dGPU**             | `supergfxctl` → Hybrid (RTX 5090 available for CUDA/games)     |
| **Display**          | Native 240Hz VRR (full panel capability)                        |
| **Keyboard BL**      | User preference                                                 |
| **Fan profile**      | Performance (via `asusctl`) — max cooling, allow full clocks    |
| **Bluetooth**        | Power on via `bluetoothctl`                                     |
| **WiFi**             | Power-save off                                                  |
| **PCIe ASPM**        | `default` (if writable, else kernel cmdline)                    |
| **PCI Runtime PM**   | Set all devices to `on` (always active, lowest latency)         |
| **USB**              | Autosuspend off (-1)                                            |
| **Audio codec**      | Power-save off + codec PM disabled                              |
| **NMI watchdog**     | On (stability monitoring during heavy loads)                    |
| **VM writeback**     | Default (500cs)                                                 |
| **NVMe scheduler**   | Set to `none` (lowest latency for fast storage)                 |

**Note**: PPD profile (`powerprofilesctl`) not needed — automated via battery saver threshold at 99%.

#### What asusctl already does vs what we add
`asusctl` on AC sets platform profile to `Performance` and switches fan curves.
But it does NOT touch these — our script must handle them:
- RAPL power limits (PL1/PL2 capping)
- `hwp_dynamic_boost` (currently 0 — free performance left off)
- EPP on individual cores (asusctl sets profile, not per-core EPP)
- `min_perf_pct` floor
- PCIe ASPM policy (if writable)
- PCI Runtime PM per-device control
- USB/audio power-save toggling
- Bluetooth power toggle
- Display refresh rate (60Hz battery / 240Hz AC, VRR auto-adapts 48-60Hz on battery)
- NMI watchdog
- NVMe I/O scheduler
- `supergfxctl` GPU mode verification (but NOT automatic switching)

---

## Step 1. Baseline & Measurement
Measure current draw before any changes.
- `powertop` (monitoring only)
- `upower -d` (discharge rate)
- Record: idle watts on battery, idle watts on AC

## Step 2. Create the Power-Switch Script
A single script: `power-switch.sh [battery|ac]`
- Applies ALL the changes from the tables above
- Fully reversible — `ac` mode undoes everything `battery` mode sets
- **Battery**: offlines 9 cores (cpu1–5, cpu10–13), keeps 7 alive (cpu0, cpu6–9, cpu14–15)
- **AC**: brings all 16 cores online, enables turbo, HWP boost, performance EPP
- USB autosuspend is **selective** — skip HID (mouse/keyboard) to avoid wake issues
- Lives in this repo, symlinked to `/usr/local/bin/`

## Step 3. Udev Rule for Auto-Triggering
- Detect AC plug/unplug events
- Call `power-switch.sh battery` or `power-switch.sh ac`
- Rule in `/etc/udev/rules.d/99-power-switch.rules`

## Step 4. ASUS-Specific Tweaks (via asusctl)
Already done / partially done:
- ✅ Auto profile switching (AC→Performance, Battery→Quiet)
- ✅ Charge limit at 80%
- ✅ Keyboard backlight off

### Fan Curve Reality (Deep Research Finding)
**Official asus-linux.org states custom fan curves are "only supported on Ryzen ROG laptops."**
Your GU605CX is Intel Arrow Lake. `asusctl` accepts the fan curve commands and
`asus_custom_fan_curve` shows `MANUAL CONTROL`, but the **EC has final authority**.

**Why fans spin when ACPI0 < 73°C:**
The Embedded Controller (EC) monitors sensors the OS cannot access (VRM, chassis skin,
internal board temps). Your visible sensors:
```
acpitz (ACPI0)  : 40°C   ← what your GNOME widget shows
TCPU            : 41°C   ← EC's own CPU reading
x86_pkg_temp    : 40°C   ← Intel package
NVMe (pci-0300) : 42.9°C ← main SSD (heat source!)
iwlwifi         : 40°C   ← WiFi adapter
SEN1/SEN2       : 31°C   ← likely VRM / chassis
```
The EC sees additional hidden sensors. When ANY internal sensor crosses its threshold,
fans spin — regardless of the `asusctl` curve. The EC also enforces a minimum RPM
floor (~2000-2500 RPM); there's no "10% speed" — it's either off or minimum.

**Strategy: Don't fight the EC, starve it of heat instead.**
- On battery: Our P-core offlining + turbo disable + dGPU off should keep ALL
  temps low enough that the EC never triggers fans in the first place.
- On AC: Let the EC do its job — use Performance profile fan curve for max cooling.

## Step 5. Display & Peripherals
- Refresh rate: 60Hz on battery, native on AC
- GNOME extension or `gnome-randr` scripting
- Bluetooth/WiFi power-save toggling in the switch script
- **OLED optimization**: Use true-black (#000000) themes in IDE/browser on battery
  - Dark GTK theme + dark browser theme = significant OLED savings

## Step 6. Kernel & Subsystem Tunables
Applied in the switch script, not globally:
- PCIe ASPM: `/sys/module/pcie_aspm/parameters/policy` (writable check, else kernel cmdline)
  - Battery: `powersupersave` — GPU slot excluded from aggressive runtime PM to prevent D3cold wake issues
  - AC: `default`
- PCI Runtime PM: `/sys/bus/pci/devices/*/power/control`
  - Battery: `auto` for all devices EXCEPT GPU (0000:01:00.0 → `on`)
  - AC: `on` for all devices
- Audio power-save: `/sys/module/snd_hda_intel/parameters/power_save`
- USB autosuspend: `/sys/bus/usb/devices/*/power/autosuspend` (selective, skip HID)
- Bluetooth: `bluetoothctl power off/on`
- WiFi power-save: `iw dev wlan0 set power_save on/off`
- Display refresh: 60Hz battery / 240Hz AC (via GNOME VRR or xrandr, auto-adapts 48-60Hz)
- NVMe scheduler: `none` on AC (lowest latency)
- NMI watchdog: `/proc/sys/kernel/nmi_watchdog`
- VM writeback: `/proc/sys/vm/dirty_writeback_centisecs`
- RAPL power limits: `/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/constraint_*`
- **dGPU D3cold verification**: `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status`

## Step 7. Final Audit

### Battery Audit
- Re-measure with `powertop` after all changes
- Verify dGPU `runtime_status` = `suspended` (not just `active`)
- Confirm idle draw is within 3–5W target
- Test that plugging in AC triggers full revert

### AC / Beast Mode Audit
- Verify all 16 cores online and boosting to max freq
- `hwp_dynamic_boost` = 1
- Platform profile = `performance`
- Run `stress-ng` or a benchmark, confirm no thermal throttling
- Verify dGPU is active and usable (e.g. `nvidia-smi`)
- Check fan curves are in performance mode (audible confirmation)
- Test that unplugging AC triggers battery mode

## Known Issues

### 1. supergfxctl Integrated Mode NOT WORKING on GU605CX (Kernel 6.19)
**Status**: Bug confirmed, workaround in place

**Root cause**: supergfxctl looks for `/sys/devices/platform/asus-nb-wmi/dgpu_disable` but kernel 6.19's new asus-armoury driver exposes it at `/sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value`

**What happens**:
- Running `supergfxctl -m Integrated` fails with "No such file or directory"
- The dGPU cannot be powered off via supergfxctl
- After logout/login, mode stays as Hybrid

**GPU power history (Feb 2026 troubleshooting session)**:
- RTX 5090 got stuck in D3cold power state after attempting Integrated mode
- nvidia-open driver (590.48.01) cannot wake GPU from D3cold → `nvidia-smi` failed
- Attempts to fix: PCI rescans, slot power cycles, udev rules, kernel params — all failed
- **Final solution**: Booted Windows, updated GPU driver/firmware → full reset cleared D3cold state
- GPU now works correctly in Hybrid mode

**Current workaround**: 
- **Keep GPU in Hybrid mode permanently** — the RTX 5090 idles at near-zero power when unused
- nvidia-open driver handles runtime D3 power management correctly in Hybrid
- Do NOT attempt to switch to Integrated mode until supergfxctl is updated
- **Script behavior**: `power-switch.sh` accepts Hybrid as correct and verifies dGPU is `suspended`; warns if in Integrated mode

**To track/fix**:
- File issue at https://gitlab.com/asus-linux/supergfxctl/-/issues
- Mention: GU605CX, kernel 6.19.2, asus-armoury driver path mismatch
- Alternatively: manually control via `echo 1 > /sys/class/firmware-attributes/asus-armoury/attributes/dgpu_disable/current_value` (RISKY — may trigger D3cold wake bug again)

**Leftover cleanup from troubleshooting**:
- ✅ Removed `/etc/modprobe.d/nvidia-d3cold-fix.conf` (fbdev=0 workaround, didn't help)
- ✅ Cleaned kernel cmdline: removed `pcie_port_pm=off pcie_aspm=off nvidia.NVreg_EnableBacklighthandler=0`
- ⚠️ `nvidia_drm.fbdev=1` kept (correct default setting)

---

## Pitfalls to Avoid (from community research)
1. **Never offline CPU 0** — it's the boot CPU, handles IRQs and timers
2. **Don't use `powertop --auto-tune` blindly** — it enables USB autosuspend on HID devices (mouse/keyboard issues)
3. **`tlp` is banned** — conflicts with `power-profiles-daemon` which `asusctl` needs
4. **D3 ≠ D3cold** — dGPU in D3 still draws ~2-5W; D3cold is near 0W. Always verify.
5. **OLED brightness ≠ LCD brightness** — content matters more than backlight slider
6. **Fan curves on Intel ROG laptops** — officially only supported on Ryzen; EC overrides at will
7. **ACPI0 ≠ EC temps** — the GNOME thermal widget shows one sensor; the EC uses many hidden ones
8. **NVMe is a heat source** — at 42.9°C idle it can trigger EC fan activation via a separate thermal path
9. **RTX 5090 + nvidia-open + D3cold = broken on kernel 6.19** — once in D3cold, GPU won't wake without Windows firmware reset
