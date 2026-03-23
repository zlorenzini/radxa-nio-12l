# Display Troubleshooting — Radxa NIO 12L

This document records the full diagnosis and fix chain for getting a desktop on an HDMI monitor running Ubuntu 22.04 with GNOME on the NIO 12L. Every step here was hit in sequence on real hardware.

**Final working config:** Xorg + GNOME Shell (GDM3), software rendering (LLVMpipe), 1920×1200 @ 60 Hz on a Samsung T260.

---

## TL;DR — What Files to Change

If you just want to apply the fixes without reading the full walkthrough:

### `/etc/gdm3/custom.conf`
```ini
[daemon]
WaylandEnable=false
```

### `/etc/X11/Xwrapper.config`
```
allowed_users=anybody
needs_root_rights=yes
```

### `/etc/X11/xorg.conf.d/10-modesetting.conf` *(create this file)*
```
Section "Device"
    Identifier "MTK GPU"
    Driver "modesetting"
    Option "AccelMethod" "none"
EndSection
```

Then restart GDM **with the monitor already connected**:
```bash
sudo systemctl restart gdm3
```

---

## Problem 1 — Wayland Session Fails Silently

### Symptom
Monitor shows no signal. GDM3 is running and appears healthy in `systemctl status` but nothing appears on screen.

### Root Cause
GDM3 defaults to launching a Wayland compositor session. On this kernel/image combination, the Wayland session for the GDM greeter fails to register a display compositor — gnome-shell starts but never acquires a Wayland surface. The screen stays black. There is no error in the GDM systemd unit logs; the failure is buried in the compositor's Wayland socket negotiation.

Additionally, early in the process, the HDMI DDC (display data channel, used to read EDID from the monitor) fails repeatedly on hot-plug:
```
mediatek-hdmi-mt8195-ddc ddc-i2c: ddc failed! : 0   (×7)
```
This is a kernel driver timing issue hitting before the monitor is ready. Connecting the monitor before powering on avoids this (see [Monitor Must Be Connected at Boot](#monitor-must-be-connected-at-boot)).

### Fix
Force GDM to use Xorg instead of Wayland.

Edit `/etc/gdm3/custom.conf`:
```ini
[daemon]
WaylandEnable=false
```

---

## Problem 2 — Xorg Blocked by Xwrapper

### Symptom
After setting `WaylandEnable=false`, GDM still shows no output. Checking the Xorg log:
```
Only console users are allowed to run the X server
Fatal server error: Server is not allowed to run
```

### Root Cause
`/etc/X11/Xwrapper.config` defaults to `allowed_users=console`, which only permits Xorg to be started from a physical TTY login. GDM runs as a system service (not a console user), so it is blocked.

### Fix
Edit `/etc/X11/Xwrapper.config`:
```
allowed_users=anybody
needs_root_rights=yes
```

`needs_root_rights=yes` is required here because the modesetting driver needs DRM master access, which on this kernel requires root. Without it Xorg starts but immediately loses DRM master and fails to initialize the display.

---

## Problem 3 — AIGLX / Glamor Crash (Missing Mali Userspace Driver)

### Symptom
Xorg now starts but immediately crashes. `/var/log/Xorg.0.log` shows:
```
(II) modeset(0): glamor X acceleration enabled on Mali-G57
(EE) AIGLX error: Calling driver entry point failed
(EE) modeset(0): Failed to create pixmap
(EE) failed to create screen resources
(EE) Server terminated with error (1).
```

### Root Cause
The modesetting driver detects the Mali-G57 GPU and automatically enables **Glamor** (an OpenGL-based 2D acceleration backend). Glamor calls into AIGLX, which tries to open the DRI driver for the Mali GPU.

The Mali-G57 is a proprietary Arm GPU. Its userspace driver (`libmali`) is a closed-source blob that is **not included** in this Ubuntu image. Without `libmali`, AIGLX has no driver entry point and fails, which causes the entire Xorg server to exit.

### Fix
Disable Glamor entirely and fall back to unaccelerated (software) rendering.

Create `/etc/X11/xorg.conf.d/10-modesetting.conf`:
```
Section "Device"
    Identifier "MTK GPU"
    Driver "modesetting"
    Option "AccelMethod" "none"
EndSection
```

`AccelMethod "none"` tells the modesetting driver not to attempt any GPU-based acceleration. X11 2D rendering falls back to **pixman** (CPU-side pixel manipulation), and composite rendering falls back to **LLVMpipe** (software GL). This is slower than hardware acceleration but fully functional.

To verify the fix before restarting GDM:
```bash
sudo timeout 5 Xorg :1 vt8
# Should exit cleanly (timeout) with no EE lines
```

---

## Problem 4 — Monitor Must Be Connected at Boot

### Symptom
After all the above fixes, GDM and gnome-shell start correctly, but if the monitor is plugged in after Xorg has already started, the screen stays black. `xrandr` shows the output as connected but Mutter (gnome-shell's compositor) has already initialized its rendering pipeline against an empty output list and does not re-initialize when the monitor appears.

### Root Cause
Xorg + modesetting driver + Mutter do not reliably hot-plug a new output into an already-running compositor session, particularly in software rendering mode where there is no GPU event loop to trigger re-enumeration.

### Fix
**Connect the monitor before powering on the board** (or before restarting GDM3).

Xorg reads the EDID at startup. With the Samsung T260 connected:
```
(II) modeset(0): EDID vendor "SAM", prod id 1013
(II) modeset(0): Output HDMI-1 connected
(II) modeset(0): Output HDMI-1 using initial mode 1920x1200 +0+0
```

Mutter then initializes its compositor against a real output and the desktop appears.

---

## Verifying the Display Stack

### Check DRM / kernel sees the monitor
```bash
cat /sys/class/drm/card0-HDMI-A-1/status    # → connected
cat /sys/class/drm/card0-HDMI-A-1/modes     # list of supported resolutions
```

### Check Xorg output configuration (with GDM running)
```bash
sudo bash -c 'DISPLAY=:0 XAUTHORITY=/run/user/131/gdm/Xauthority xrandr'
```

Expected:
```
Screen 0: minimum 320 x 200, current 1920 x 1200, maximum 4096 x 4096
HDMI-1 connected primary 1920x1200+0+0 ...
   1920x1200     59.95*+
   ...
```

### Check that gnome-shell is running
```bash
ps aux | grep gnome-shell | grep -v grep
# Should show a process owned by uid 131 (gdm) with significant RSS
```

### Check Xorg log for errors
```bash
grep -E '^.*\(EE\)' /var/log/Xorg.0.log
# Should be empty after the AccelMethod fix
```

---

## Summary of All Changes

| File | Change | Reason |
|------|--------|--------|
| `/etc/gdm3/custom.conf` | `WaylandEnable=false` | Wayland greeter fails silently; Xorg works |
| `/etc/X11/Xwrapper.config` | `allowed_users=anybody` + `needs_root_rights=yes` | GDM is not a console user; modesetting needs DRM master |
| `/etc/X11/xorg.conf.d/10-modesetting.conf` | `AccelMethod "none"` | Mali-G57 `libmali` absent; Glamor crashes Xorg |

---

## Do Not Change AccelMethod

`Option "AccelMethod" "none"` in `/etc/X11/xorg.conf.d/10-modesetting.conf` is a **required workaround**, not a placeholder. Do not change it to `"glamor"` or remove it. Without it:

1. Xorg loads Glamor, which calls the AIGLX driver entry point for the Mali-G57.
2. `libmali` is absent → `AIGLX error: Calling driver entry point failed`.
3. Xorg exits with `Failed to create pixmap` / error code 1.
4. GDM immediately respawns Xorg, which crashes again — continuous crash loop.

If you want GPU acceleration, install `libmali` first (see [`gpu-acceleration.md`](gpu-acceleration.md)), then and only then change `AccelMethod` back to `"glamor"`.

> **The file is protected with `chattr +i` on the running board.** You cannot edit it without first running `sudo chattr -i /etc/X11/xorg.conf.d/10-modesetting.conf`. This is intentional — an AI agent repeatedly changed it back to `"glamor"` and crashed the display.

---

## Known Remaining Issues

- **Software rendering only:** The desktop runs on LLVMpipe. Basic desktop use is fine; video playback and 3D applications will be slow. See [`gpu-acceleration.md`](gpu-acceleration.md) for the path to hardware acceleration.
- **No hot-plug:** Connecting a monitor after GDM has started does not produce a display. Restart GDM after plugging in the monitor if needed: `sudo systemctl restart gdm3`.
- **DDC flicker on hot-plug:** A small number of DDC read failures appear in `dmesg` when hotplugging, but these are cosmetic once the issue is avoided by pre-connecting the monitor.
