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

Backup of original: SHA256 `2d9e69a09275423c550ef0ffb5ef468021b8d05deb6c0b8a4f98d69bd3a9b853`. Note: backup was at `/tmp/gpu-mali.dtbo.bak` and **will not survive a reboot** — if rollback is needed post-reboot, rebuild from the patched DTS source in this repo at `docs/gpu-mali-patched.dts` (or use `dtc -I dtb -O dts /dev/sdc3-mounted-path/gpu-mali.dtbo` to inspect what's there).

Patched DTS source committed to this repo at `docs/gpu-mali-patched.dts`.

### Verified after reboot (2026-03-23, Armbian)

**Important:** Armbian uses the **mainline kernel** (6.19.0-rc5-edge-genio) which loads **Panfrost** (open-source Mesa driver), NOT the proprietary Mali blob. `/dev/mali0` does not exist. All the `libmali` / `mali-egl-fix.so` / Glamor notes below are only relevant when booting the Ubuntu BSP kernel.

Results:
1. `sudo dmesg | grep -i mali` → `panfrost 13000000.gpu: mali-g57 id 0x9093` — no devfreq errors ✓
2. `cat /sys/bus/platform/devices/13000000.gpu/devfreq/13000000.gpu/cur_freq` → 390000000 at idle ✓
3. 16 OPP levels available (390–880 MHz), governor: `simple_ondemand` — full DVFS working ✓
4. GNOME Shell on Wayland using `gbm renderer` for `/dev/dri/card0` — GPU-accelerated ✓
5. Active DRM clients: gnome-shell, Xwayland, firefox, code — all on renderD128 ✓

**In Armbian/Panfrost there is nothing further to do.** GPU acceleration is fully working out of the box. No Glamor config, no EGL shim needed.

## Rule

Do NOT change `AccelMethod` to `"glamor"` without FIRST:
1. Ensuring the mali-egl-fix shim is installed to `/usr/local/lib/mali-egl-fix.so`
2. Ensuring the GDM systemd drop-in (`/etc/systemd/system/gdm3.service.d/mali-egl-fix.conf`) sets `LD_PRELOAD=/usr/local/lib/mali-egl-fix.so`

Both steps are handled by `~/mali-glamor-enable.sh`.

Always read these files before changing any display or GPU configuration:

    /home/ubuntu/repos/radxa-nio-12l/docs/display-troubleshooting.md
    /home/ubuntu/repos/radxa-nio-12l/docs/gpu-acceleration.md

---

## Shutdown Recovery Log

### 2026-04-11: Video/DMA resume failure (IOMMU + SWIOTLB)

Observed kernel errors during video path bring-up/resume:

```
Cannot accommodate DMA translation for IOMMU page tables
swiotlb buffer is full (sz: 1048576 bytes), total 32768 (slots), used 4 (slots)
```

Interpretation:
- DMA mappings for multimedia buffers exceeded available bounce-buffer/IOMMU translation headroom.
- This is usually a memory-pool sizing issue, not a userspace app issue.

Persistent fix prepared in Armbian build tree (board defaults):
- File changed: `/home/zach/Documents/build/config/boards/radxa-nio-12l.conf`
- `SRC_CMDLINE` now includes:
    - `cma=4096M`
    - `swiotlb=262144`

Result: newly built images for `radxa-nio-12l` will boot with larger DMA pools by default.

On-board verification after booting a rebuilt image:

```bash
cat /proc/cmdline
dmesg | grep -Ei 'swiotlb|iommu|dma translation|buffer is full'
```

Expected:
- `/proc/cmdline` includes `cma=4096M` and `swiotlb=262144`
- No recurring `Cannot accommodate DMA translation` or `swiotlb buffer is full` during video workloads.

Rollback path:
- Revert that board config change in `build/config/boards/radxa-nio-12l.conf`
- Rebuild and flash/install the previous kernel/image.

## Continuity Rule for Future Agents

After any risky or recovery-relevant change, append a short entry here with:
1. Date and symptom/error text.
2. Exact file(s) changed and key parameters.
3. Verification commands.
4. Rollback command/path.

Keep entries concise and chronological so recovery is possible after an unexpected shutdown.

### 2026-04-11: Kernel build completed (Armbian compile.sh kernel)

Build command used:

```bash
cd /home/zach/Documents/build
./compile.sh kernel BOARD=radxa-nio-12l BRANCH=edge KERNEL_CONFIGURE=no
```

Artifacts confirmed in `output/debs` (latest set at 06:09):
- `linux-image-edge-genio_26.05.0-trunk_arm64__1-Sd195-D0000-Pc5d4-C48a8-Hec90-HK01ba-Vc222-Bdc65-R448a.deb`
- `linux-dtb-edge-genio_26.05.0-trunk_arm64__1-Sd195-D0000-Pc5d4-C48a8-Hec90-HK01ba-Vc222-Bdc65-R448a.deb`
- `linux-headers-edge-genio_26.05.0-trunk_arm64__1-Sd195-D0000-Pc5d4-C48a8-Hec90-HK01ba-Vc222-Bdc65-R448a.deb`

Important deployment caveat:
- This `compile.sh kernel` target updates kernel/DTB packages.
- Board `SRC_CMDLINE` changes in `build/config/boards/radxa-nio-12l.conf` may still require updating runtime boot args on-device (`/boot/armbianEnv.txt`) or building full image/BSP path, depending on current boot flow.

Post-install check on board:

```bash
cat /proc/cmdline
```

If `cma=4096M swiotlb=262144` is missing, add them under `extraargs=` in `/boot/armbianEnv.txt` and reboot.

### 2026-04-11: Attempting kernel switch now

Status: in progress

Run steps are documented in:
- `/home/zach/Documents/radxa-nio-12l/docs/kernel-switch-runbook.md`

Current intent:
1. Install newly built `linux-image-edge-genio` and `linux-dtb-edge-genio` packages.
2. Reboot into the new kernel.
3. Verify `cma=4096M swiotlb=262144` in `/proc/cmdline`.
4. Re-test for absence of prior DMA/IOMMU video errors.

If boot args are missing post-reboot, set `extraargs=cma=4096M swiotlb=262144` in `/boot/armbianEnv.txt` and reboot.

### 2026-04-11: Configs moved into this repo for commit

To avoid losing board config tweaks when the Armbian build repo is refreshed, the modified board config is now tracked here:

- `/home/zach/Documents/radxa-nio-12l/kernel/userpatches/config/boards/radxa-nio-12l.conf`

Reapply into Armbian build tree before compile:

```bash
cp /home/zach/Documents/radxa-nio-12l/kernel/userpatches/config/boards/radxa-nio-12l.conf \
    /home/zach/Documents/build/config/boards/radxa-nio-12l.conf
```
