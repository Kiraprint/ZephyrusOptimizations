# NVIDIA nvidia-powerd Service

**Status:** Re-enabled (important for power management)

## What nvidia-powerd does

This is NVIDIA's **Dynamic Boost** daemon for Optimus laptops. It:

- Manages GPU power allocation dynamically
- Controls TGP (Total Graphics Power) limits
- Handles dynamic power sharing between CPU and GPU
- Required for GPU to reach max TDP under load

## Why it keeps dGPU awake at 8W

In Optimus mode with `nvidia-drm.modeset=0`, nvidia-powerd keeps the GPU in a "ready" state:
- 8W idle power (monitoring/standby)
- Can quickly boost to full power when workload starts
- Better than 32W (when actively used)
- Worse than 0-2W (deep sleep)

## The tradeoff

| Scenario | nvidia-powerd | Idle Power | Max Performance |
|----------|---------------|------------|-----------------|
| **Disabled** | ❌ | ~8W (stuck) | Limited TDP ❌ |
| **Enabled** | ✅ | ~8W (managed) | Full TDP ✅ |

## For your use case (ML/Gaming)

**KEEP IT ENABLED** - You want maximum dGPU power when running workloads.

The 8W idle is acceptable if you need the dGPU ready for:
- ML training
- CUDA workloads
- Gaming

## Current power limit status

```
power.limit: [N/A] (dynamic, controlled by firmware + nvidia-powerd)
power.max_limit: 175W (vBIOS capability)
Actual limit under load: 110W (firmware-enforced, as we discovered)
```

## If you want deeper sleep (0-2W)

You'd need to:
1. Disable nvidia-powerd
2. Remove `nvidia-drm.modeset=0`
3. Accept: Boot logo duplication + slower wake-up from D3cold

**Not recommended for your workflow.**

