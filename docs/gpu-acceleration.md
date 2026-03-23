# GPU Acceleration — Mali-G57 on the NIO 12L

## Current State

The NIO 12L uses a **Mali-G57 MC5** GPU (part of Arm's Bifrost architecture family, kernel driver `arm,mali-midgard` on `/dev/mali0`).

**As of 2026-03-22:** `libmali-mtk-8195` **r48p0** is installed (`48p0+git20241205.ba78630-0ubuntu5`). The EGL, GLES, and GBM system symlinks all point to the Mali blob at `/usr/lib/aarch64-linux-gnu/mt8195/lib/libmali.so.0.48.0`. The DRI driver `mali-dp_dri.so` is present in `/usr/lib/aarch64-linux-gnu/dri/`.

Despite `libmali` being installed, Xorg Glamor is still **disabled** as of now. The reason: r48p0 supports `EGL_EXT_image_dma_buf_import` but does **not** support `EGL_KHR_image_pixmap`. Xorg glamor calls `epoxy_eglCreateImageKHR(EGL_NATIVE_PIXMAP_KHR)`, which the blob rejects, causing Xorg to abort.

**Workaround in progress:** A small LD_PRELOAD shim (`mali-egl-fix.c` → `/tmp/mali-egl-fix/mali-egl-fix.so`) intercepts `epoxy_eglCreateImageKHR` calls with target `EGL_NATIVE_PIXMAP_KHR` and converts them to `EGL_LINUX_DMA_BUF_EXT` (exporting the GBM BO as a DMA-BUF fd first). This matches extensions the Mali blob does support.

To enable Glamor, run:
```bash
sudo bash ~/mali-glamor-enable.sh
```
(Script at `~/mali-glamor-enable.sh`. See script comments for what it does and how to undo.)

Current status:
- OpenGL ES → available (via `libmali` r48p0)
- Vulkan → available (Vulkan ICD at `/usr/lib/aarch64-linux-gnu/mt8195/vulkan/mali.json`)
- Xorg Glamor (2D accel) → **not yet enabled** — shim installed, pending reboot to pick up DT fix
- LLVMpipe (software GL) → still active fallback until Glamor is enabled
- VPU / video decode → untested (see end of doc)
- GPU devfreq/OPP → **power regulation fix pending reboot** (see below)

### Power Regulation Issue — mali-supply vs mali_sram-supply

The Mali driver registers two power supplies via `supply-names = "mali\0mali_sram"` in the device tree. The `gpu-mali.dtbo` overlay (applied by U-Boot at boot) originally set:
- `mali-supply` → `mt6315_7_vbuck1` (Vgpu, MT6315 PMIC on SPMI bus) ✓
- `mali_sram-supply` → `mt6359_vsram_others_ldo_reg` (vsram_others, MT6359 PMIC on pwrap) ✗

The mismatch caused:
```
devfreq 13000000.mali: Couldn't update frequency transition information.
```
at every boot, leaving the GPU permanently at the lowest OPP (390 MHz) with no frequency scaling.

**Fix (2026-03-23):** Both supplies now reference `mt6315_7_vbuck1`. The `__fixups__` section of `gpu-mali.dtbo` was changed so `mt6315_7_vbuck1` resolves both `mali-supply` and `mali_sram-supply`. With one physical regulator serving both consumers, the regulator framework holds Vgpu at the max of both OPP voltage requests (750 mV constant — slightly less efficient but frequency scaling now works).

The patched DTBO is in the firmware partition at `/dev/sdc3` → `FIRMWARE/mediatek/genio-1200-evk-ufs/gpu-mali.dtbo`. The DTS source is at `/tmp/gpu-mali-patched.dts`.

To roll back:
```bash
sudo mkdir -p /mnt/fw
sudo mount -o rw /dev/sdc3 /mnt/fw
sudo cp /tmp/gpu-mali.dtbo.bak /mnt/fw/FIRMWARE/mediatek/genio-1200-evk-ufs/gpu-mali.dtbo
sudo sync && sudo umount /mnt/fw
```

---

## What You Need (Completed)

`libmali-mtk-8195` (r48p0) is now installed. The package provides EGL 1.4, OpenGL ES 1.1/2.0/3.1/3.2, OpenCL 2.0, and Vulkan 1.1. The system symlinks point at it.

The remaining step is enabling Glamor with the LD_PRELOAD shim; see **Current State** above.

---

## EGL Platform Notes

The r48p0 blob advertises these client extensions:
```
EGL_KHR_platform_gbm  EGL_KHR_platform_wayland  EGL_EXT_platform_wayland
```
It uses the **GBM EGL platform** for Xorg Glamor (exactly what Xorg's modesetting driver needs).

Supported image extensions include:
- `EGL_KHR_image`, `EGL_KHR_image_base` ✓
- `EGL_EXT_image_dma_buf_import`, `EGL_EXT_image_dma_buf_import_modifiers` ✓
- `EGL_KHR_image_pixmap` ✗ (this is why the mali-egl-fix shim is needed)

---

## Finding libmali for the Genio 1200

### Option 1 — Radxa / IoT Yocto BSP

MediaTek and Radxa provide `libmali` as part of their Yocto-based Linux BSP for the Genio 1200. The relevant package is sometimes called `libmali-bifrost-g57` or `libmali-mt8395`.

Check if Radxa has published an apt repository for Ubuntu packages:
```bash
# On the board:
apt-cache search libmali
# Or check Radxa's package server:
# https://github.com/radxa-pkg  (search for mali or libmali)
```

### Option 2 — IoT Yocto SDK Extraction

If you have access to the MediaTek IoT Yocto SDK for MT8395:
```
meta-mediatek-mt8395/recipes-graphics/libmali/
```
The `.so` files can be extracted and installed manually. You need the variant matching your kernel ABI and GPU configuration.

### Option 3 — Panfrost (Open Source, Long Term)

[Panfrost](https://docs.mesa3d.org/drivers/panfrost.html) is the open-source reverse-engineered driver for Arm Mali GPUs (Midgard, Bifrost, Valhall). Mali-G57 is Bifrost.

Panfrost support for Mali-G57 (G57 = Bifrost Gen 3) is available in Mesa 22+ but **kernel support depends on the DRM driver**. The `5.15.0-1029-mtk` kernel uses a MediaTek-patched DRM that may or may not expose the standard `panfrost` interface.

Check:
```bash
# Does the kernel have panfrost?
lsmod | grep panfrost
modinfo panfrost 2>/dev/null

# What DRM driver is bound to the GPU?
dmesg | grep -iE 'mali|panfrost|gpu'
ls /dev/dri/
```

If `panfrost` is available and bound, Mesa's Panfrost driver may work with a newer Mesa:
```bash
# Check Mesa version
glxinfo 2>/dev/null | grep "OpenGL renderer"
# Install newer Mesa if needed (via ubuntu-toolchain-r or oibaf PPA — aarch64 support varies)
```

---

## Installing libmali (when available)

Once you have the `.so` file(s), the basic installation pattern:

```bash
# Example — adjust filename to match actual file
sudo cp libmali-bifrost-g57-*.so /usr/lib/aarch64-linux-gnu/
sudo ln -sf libmali-bifrost-g57-<version>.so /usr/lib/aarch64-linux-gnu/libmali.so.1
sudo ln -sf libmali.so.1 /usr/lib/aarch64-linux-gnu/libmali.so
sudo ldconfig
```

libmali typically also replaces (or supplements) the OpenGL ES and EGL stubs:
```bash
# libmali often ships as a drop-in for these:
sudo ln -sf libmali.so /usr/lib/aarch64-linux-gnu/libGLESv2.so.2
sudo ln -sf libmali.so /usr/lib/aarch64-linux-gnu/libEGL.so.1
```

After installing libmali, **re-enable Glamor** by removing (or editing) the `AccelMethod "none"` xorg.conf.d entry and restarting GDM.

---

## Re-enabling Glamor After Installing libmali

Edit `/etc/X11/xorg.conf.d/10-modesetting.conf` — remove the `AccelMethod "none"` line or delete the file entirely:

```bash
sudo rm /etc/X11/xorg.conf.d/10-modesetting.conf
sudo systemctl restart gdm3
```

Verify acceleration:
```bash
sudo bash -c 'DISPLAY=:0 XAUTHORITY=/run/user/131/gdm/Xauthority glxinfo | grep -E "renderer|vendor"'
# Should show "Mali-G57" rather than "llvmpipe"
```

---

## Video Decode Acceleration

The SoC has a hardware VPU (H.264, H.265, VP9). The kernel exposes it as a V4L2 M2M device. VA-API or GStreamer with a v4l2 plugin may be able to use it:

```bash
ls /dev/video*
v4l2-ctl --list-devices 2>/dev/null
```

GStreamer pipeline test:
```bash
sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
gst-launch-1.0 filesrc location=test.mp4 ! qtdemux ! h264parse ! v4l2h264dec ! ...
```

This is not yet fully configured — tracked as future work in [`embedded-dev.md`](embedded-dev.md).

---

## Summary

| Feature | Status | Notes |
|---------|--------|-------|
| 3D acceleration (OpenGL ES) | ✅ Available | `libmali` r48p0 installed |
| Vulkan | ✅ Available | Mali Vulkan ICD installed |
| Xorg Glamor (2D accel) | ⚠️ Not yet enabled | Requires mali-egl-fix shim + GDM restart (run `~/mali-glamor-enable.sh`) |
| LLVMpipe (software GL) | ✅ Working | Current fallback until Glamor is enabled |
| Panfrost open driver | ⚠️ N/A | Kernel uses proprietary mali kbase (not panfrost); `/dev/mali0` not `/dev/dri/renderD128` |
| VPU / video decode | ⚠️ Untested | V4L2 M2M device present, not configured |
