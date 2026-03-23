# Notes for the Copilot Agent on this system

## MANDATORY: Pre-Action Logging

**Before taking any action that could break the display or require a reboot to recover, you MUST write a log entry to `~/agent-work.log` first.**

This includes (but is not limited to):
- Editing any file under `/etc/X11/`, `/etc/gdm3/`, `/etc/systemd/`, `/usr/local/lib/`, or `/usr/lib/`
- Running `sudo systemctl restart gdm3` or any other service restart
- Installing or removing packages
- Running any script that does any of the above

The log entry must be written **before** the action, not after. Format:

```bash
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ABOUT TO: <plain English description of what you are about to do and why>" >> ~/agent-work.log
echo "  Files affected: <list>" >> ~/agent-work.log
echo "  Rollback: <how to undo this if it breaks>" >> ~/agent-work.log
```

Then, after the action completes successfully:

```bash
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DONE: <what was done>" >> ~/agent-work.log
```

If the system becomes unresponsive after your action, the user will SSH in and read `~/agent-work.log` to know exactly what you were doing and how to undo it. **If the log is missing or incomplete, recovery is much harder.**

---

## What you did wrong (and what was fixed)

A previous agent changed `/etc/X11/xorg.conf.d/10-modesetting.conf` and set:

    Option "AccelMethod" "glamor"

This broke the display. Another agent fixed it by restoring:

    Option "AccelMethod" "none"

The crash error was:
```
(EE) AIGLX error: Calling driver entry point failed
(EE) modeset(0): Failed to create pixmap
(EE) Server terminated with error (1)
```

## Why it crashed — the real root cause

`libmali-mtk-8195` r48p0 IS installed (since 2026-03-22). However it does **not** support `EGL_KHR_image_pixmap`. When Glamor is enabled, Xorg's glamor module calls `epoxy_eglCreateImageKHR(EGL_NATIVE_PIXMAP_KHR)`. The Mali blob rejects this and returns `EGL_NO_IMAGE_KHR`, causing Xorg to abort.

The fix is an LD_PRELOAD shim (`/tmp/mali-egl-fix/mali-egl-fix.so`) that intercepts `epoxy_eglCreateImageKHR` calls with `EGL_NATIVE_PIXMAP_KHR` and converts them to `EGL_LINUX_DMA_BUF_EXT` (which the blob does support).

## Current state

- `/etc/X11/xorg.conf.d/10-modesetting.conf` has `AccelMethod "none"` — this is safe but disables GPU acceleration
- The mali-egl-fix shim is installed at `/usr/local/lib/mali-egl-fix.so`
- GDM drop-in at `/etc/systemd/system/gdm3.service.d/mali-egl-fix.conf` sets `LD_PRELOAD`
- An install script is at `~/mali-glamor-enable.sh` — run it with `sudo bash ~/mali-glamor-enable.sh`

### Power regulation fix (2026-03-23)

The devfreq/OPP system failed at boot with `Couldn't update frequency transition information`. Root cause: `gpu-mali.dtbo` set `mali_sram-supply = <&mt6359_vsram_others_ldo_reg>` but it should be `<&mt6315_7_vbuck1>` (same as `mali-supply`).

**Fix applied:** `/FIRMWARE/mediatek/genio-1200-evk-ufs/gpu-mali.dtbo` on the firmware partition (`/dev/sdc3`) was patched. The `__fixups__` `mt6359_vsram_others_ldo_reg` entry was removed and `mt6315_7_vbuck1` now resolves both `mali-supply` and `mali_sram-supply`. **Reboot required.**

Backup of original at `/tmp/gpu-mali.dtbo.bak` (SHA256: `2d9e69a09275423c550ef0ffb5ef468021b8d05deb6c0b8a4f98d69bd3a9b853`).

Patched DTS source at `/tmp/gpu-mali-patched.dts`.

## Rule

Do NOT change `AccelMethod` to `"glamor"` without FIRST:
1. Ensuring the mali-egl-fix shim is installed to `/usr/local/lib/mali-egl-fix.so`
2. Ensuring the GDM systemd drop-in (`/etc/systemd/system/gdm3.service.d/mali-egl-fix.conf`) sets `LD_PRELOAD=/usr/local/lib/mali-egl-fix.so`

Both steps are handled by `~/mali-glamor-enable.sh`.

Always read these files before changing any display or GPU configuration:

    /home/ubuntu/repos/radxa-nio-12l/docs/display-troubleshooting.md
    /home/ubuntu/repos/radxa-nio-12l/docs/gpu-acceleration.md
