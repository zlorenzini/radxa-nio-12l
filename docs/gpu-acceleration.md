# GPU Acceleration — Mali-G57 on the NIO 12L

## Current State (Armbian, kernel 6.19)

The NIO 12L uses a **Mali-G57 MC5** GPU (Arm Bifrost architecture). Under Armbian with kernel 6.19, the active driver is **Panfrost** (open source, DRM/KMS), backed by **Mesa 25.2.8**. OpenGL ES 3.1 and OpenGL 3.1 are fully functional.

**glmark2-es2-wayland score: 2699.** See [docs/benchmarks.md](benchmarks.md) for full results.

| Feature | Status | Notes |
|---------|--------|-------|
| OpenGL ES 3.1 | ✅ Working | Panfrost / Mesa 25.2.8 |
| OpenGL 3.1 | ✅ Working | Panfrost / Mesa 25.2.8 |
| Vulkan | ❌ Not available | panvk Bifrost support not present in Mesa 25.2 |
| GPU DVFS | ✅ Working | 16 OPP levels, 390–880 MHz (after `mali_sram-supply` fix — see Fix 1) |
| GPU stability | ✅ Stable | AFBC corruption fixed via `PAN_MESA_DEBUG=noafbc` (see Fix 2) |
| VPU / video decode | ⚠️ Untested | V4L2 M2M device present, not configured |
| NPU | ⚠️ Untested | See `install-genio-neuropilot.sh` |

---

## Fix 1 — GPU DVFS: mali_sram-supply Device Tree Patch

### Symptom

GPU locked permanently at the lowest OPP (390 MHz). At every boot, dmesg shows:

```
devfreq 13000000.mali: Couldn't update frequency transition information.
```

### Root Cause

The Mali driver registers two power supplies via `supply-names = "mali\0mali_sram"` in the device tree. The stock `gpu-mali.dtbo` overlay wired them as:

- `mali-supply` → `mt6315_7_vbuck1` (Vgpu, MT6315 PMIC on SPMI bus) ✓
- `mali_sram-supply` → `mt6359_vsram_others_ldo_reg` (vsram_others, MT6359 PMIC on pwrap) ✗

The wrong PMIC reference for `mali_sram-supply` caused the regulator framework to fail, and the driver disabled DVFS entirely.

### Fix Applied (2026-03-23)

Both `mali-supply` and `mali_sram-supply` now reference `mt6315_7_vbuck1`. The `__fixups__` section of `gpu-mali.dtbo` was updated so `mt6315_7_vbuck1` resolves both consumers. With one physical regulator serving both, the framework holds Vgpu at the max of both OPP voltage requests (750 mV constant — slightly less efficient but all 16 OPP levels now work).

The patched DTBO is stored in the firmware partition at `/dev/sdc3` → `FIRMWARE/mediatek/genio-1200-evk-ufs/gpu-mali.dtbo`. The DTS source is at `docs/gpu-mali-patched.dts`.

### Verification

```bash
# List all available GPU frequencies
cat /sys/class/devfreq/13000000.gpu/available_frequencies

# Check current operating frequency
cat /sys/class/devfreq/13000000.gpu/cur_freq
```

### Rollback

```bash
sudo mkdir -p /mnt/fw
sudo mount -o rw /dev/sdc3 /mnt/fw
sudo cp /tmp/gpu-mali.dtbo.bak /mnt/fw/FIRMWARE/mediatek/genio-1200-evk-ufs/gpu-mali.dtbo
sudo sync && sudo umount /mnt/fw
```

---

## Fix 2 — GPU Stability: AFBC Corruption (JOB_STATUS_INVALID_DATA_FAULT)

### Symptom

After hours of browser use (Chromium or Firefox equally), the display glitches and dmesg shows:

```
panfrost 13000000.gpu: JOB_STATUS_INVALID_DATA_FAULT
```

### Root Cause

AFBC (Arm Frame Buffer Compression) generates malformed job descriptors under sustained EGL compositor load on kernel 6.19 / Mesa 25.2. This is a known Panfrost/Bifrost bug.

### Failed Workaround

Adding `panfrost.no_afbc=1` to the kernel command line has no effect — this parameter does not exist in the 6.19 Panfrost driver and is silently ignored:

```
panfrost: unknown parameter 'no_afbc' ignored
```

### Correct Fix

Disable AFBC at the Mesa level by setting the `PAN_MESA_DEBUG=noafbc` environment variable. Add it to `~/.bashrc`:

```bash
export PAN_MESA_DEBUG=noafbc
```

**Result:** Confirmed stable — 5+ days uptime with browser open, zero `JOB_STATUS_INVALID_DATA_FAULT` faults after applying the fix.

> **Note for image builders:** Set this system-wide by adding it to `/etc/environment` or creating `/etc/profile.d/panfrost.sh`:
> ```bash
> echo 'export PAN_MESA_DEBUG=noafbc' | sudo tee /etc/profile.d/panfrost.sh
> ```

---

## SVS (Smart Voltage Scaling)

MediaTek SVS (Smart Voltage Scaling) runs at boot and sets per-OPP voltage margins for the GPU, split into two bands: `SVSB_GPU_LOW` and `SVSB_GPU_HIGH`. These are visible in dmesg as `svs_init02_isr_handler` entries for each band.

The band split occurs around 640–670 MHz. SVS operates correctly once the `mali_sram-supply` fix (Fix 1) is in place and `PAN_MESA_DEBUG=noafbc` is set (Fix 2).

---

## Video Decode (VPU)

The MT8395 SoC includes a hardware VPU supporting H.264, H.265, and VP9, exposed as a V4L2 M2M device.

This has not yet been configured or tested. To inspect available devices:

```bash
ls /dev/video*
v4l2-ctl --list-devices 2>/dev/null
```

Tracked as future work in [embedded-dev.md](embedded-dev.md).

---

## Historical Reference — Ubuntu / libmali Era

Prior to the switch to Armbian, the board ran Ubuntu with the proprietary **`libmali-mtk-8195` r48p0** blob (`48p0+git20241205.ba78630-0ubuntu5`). Key characteristics of that setup:

- GPU accessed via `/dev/mali0` (mali kbase driver, not Panfrost/DRM)
- Vulkan was available via the blob's ICD at `/usr/lib/aarch64-linux-gnu/mt8195/vulkan/mali.json`
- Xorg Glamor required an LD_PRELOAD shim (`mali-egl-fix.so`) to work around the missing `EGL_KHR_image_pixmap` extension; the blob supported `EGL_EXT_image_dma_buf_import` but not `EGL_KHR_image_pixmap`, causing Xorg to abort
- The same `mali_sram-supply` DVFS bug existed and the same fix was applied
- LLVMpipe was the active software GL fallback when Glamor was not enabled

That setup was abandoned in favour of Panfrost for an open-source, mainline-aligned stack and better sustained performance.
