# GPU Acceleration — Mali-G57 on the NIO 12L

## Current State

The NIO 12L uses a **Mali-G57 MC5** GPU (part of Arm's Bifrost architecture family). As of the Ubuntu 22.04 `baoshan-classic-desktop` image (kernel `5.15.0-1029-mtk`), **no userspace GPU driver is included**.

The DRM kernel driver (`panfrost` or MediaTek's proprietary variant) is present and functional — the kernel sees the GPU. But without a userspace driver, nothing above the kernel can use it:

- OpenGL ES → not available
- Vulkan → not available
- Video decode acceleration (V4L2 M2M) → partially available (kernel-side only)
- 2D Glamor acceleration in Xorg → disabled as a workaround (see [`display-troubleshooting.md`](display-troubleshooting.md))

The desktop currently renders using **LLVMpipe** (software OpenGL via Mesa's LLVM backend) and **pixman** (software 2D). This is usable for general desktop work but is slow for anything graphics-intensive.

---

## What You Need

The Mali-G57 requires **`libmali`** — Arm's proprietary binary userspace driver blob. It provides:
- OpenGL ES 1.1 / 2.0 / 3.1 / 3.2
- EGL
- Vulkan 1.1 (on some variants)
- OpenCL 2.0 (on some variants)

`libmali` is not open source. It is distributed by Arm and SoC vendors under a license that permits redistribution as part of a board support package (BSP).

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
| 3D acceleration (OpenGL ES) | ❌ Not working | `libmali` not in image |
| Vulkan | ❌ Not working | Requires `libmali` with Vulkan variant |
| Xorg Glamor (2D accel) | ❌ Disabled | Disabled as workaround; requires `libmali` |
| LLVMpipe (software GL) | ✅ Working | Current fallback |
| Panfrost open driver | ⚠️ Untested | Depends on kernel DRM driver interface |
| VPU / video decode | ⚠️ Untested | V4L2 M2M device present, not configured |
