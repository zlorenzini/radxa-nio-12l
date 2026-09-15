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

### 2026-06-27: IRQ 116 storm and mt6360 regulator failures (Armbian 6.19.8-edge-genio)

**Symptom:** At every boot, ~54 seconds after kernel start:
```
mt6360-regulator mt6360-regulator.7.auto: Failed to register  4 regulator
mt6360 5-0034: Failed to create device link (0x180) with supplier regulator-vsys-buck
mt6360-tcpc mt6360-tcpc.8.auto: Failed to register tcpci port
irq 116: nobody cared (try booting with the "irqpoll" option)
Disabling IRQ #116
```

**Root cause (two issues):**

1. `LDO_VIN1-supply = <&vsys_buck>` — kernel 6.19 `device_link_add()` with `DL_FLAG_PM_RUNTIME` fails when creating a link to a fixed regulator that hasn't completed PM runtime init. Affects ldo1 (ext_lcd_3v3), ldo2 (panel1_p1v8), ldo3 (vmc_pmu/SD card signal voltage).

2. `LDO_VIN3-supply = <&buck2>` — `buck2` is a sibling sub-node of `mt6360-regulator` itself. Linking an MFD device to its own sub-regulator fails. Affects ldo6 and ldo7 (emi_vmddr_en).

3. The `tcpci_mt6360` module (`CONFIG_TYPEC_MT6360=m`) loads, partially inits, holds the PD_IRQB line (EINT 100, level-low, IRQ 116) asserted, fires ~100k times, then the kernel disables the IRQ. USB-C PD was already broken by the upstream regulator failures.

**Fix applied (2026-06-27):**
- `/etc/modprobe.d/disable-mt6360-tcpc.conf` → `blacklist tcpci_mt6360`
  - Stops the module from loading; EINT 100 stays masked; no interrupt storm
  - USB-C PD was already non-functional
- `/boot/armbianEnv.txt` → added `extraargs=cma=256M swiotlb=262144`
  - Restored DMA fix (lost in reflash) for IOMMU/video DMA errors
  - Note: originally set to `cma=4096M` but that silently fails on this board (DRAM layout can't satisfy 4 GiB contiguous); lowered to 256M on 2026-06-28

**Rollback (blacklist):** `sudo rm /etc/modprobe.d/disable-mt6360-tcpc.conf && reboot`
**Rollback (boot args):** Remove the `extraargs=` line from `/boot/armbianEnv.txt` and reboot.

**Upstream fix pending:** Patch series `arm64: dts: mediatek: mt8395-kontron-i1200: Fix MT6360 regulator nodes` (LKML 2025/7/24/454, same SoC family) likely contains the DTS fix for the LDO_VIN1/LDO_VIN3 supply chain. Check Armbian edge-genio updates — when it lands, `tcpci_mt6360` can be un-blacklisted and SD card signal voltage / panel power may start working.

**Verification after reboot:**
```bash
cat /proc/cmdline                                      # should show cma=256M swiotlb=262144
journalctl -k | grep "irq 116\|nobody cared"          # should be empty
journalctl -k | grep "mt6360-tcpc"                    # should be absent (module blacklisted)
lsmod | grep tcpci_mt6360                             # should be empty
```

### 2026-06-28: Stability fixes — AFBC, persistent journal, panic reboot

**Symptom:** System rebooted after ~4 hours of uptime. Hardware watchdog (MTK WDT, 31 s) fired — most likely a Panfrost GPU job fault escalating to a kernel hard lockup.

**Root causes identified:**

1. `PAN_MESA_DEBUG=noafbc` was **never applied** to the running system despite being documented as the fix. AFBC corruption causes `JOB_STATUS_INVALID_DATA_FAULT` GPU resets under sustained EGL/browser load, which can escalate to a driver hang and watchdog reset.

2. Journal storage was `volatile` — crash evidence was lost on every reboot, making diagnosis impossible.

3. `cma=4096M` silently fails at boot (`cma: Failed to reserve 4096 MiB`; CmaTotal=0). IOMMU is in Translated mode so DMA works without CMA, but the failing reservation produces noise. Lowered to `cma=256M`.

**Fixes applied (2026-06-28):**

- `~/.config/environment.d/panfrost.conf` → `PAN_MESA_DEBUG=noafbc`
  - systemd user-session environment; picked up by GNOME/Wayland on login
- `~/.bashrc` → `export PAN_MESA_DEBUG=noafbc`
  - covers interactive terminal sessions
- `sudo bash ~/fix-stability.sh` (run once by user) writes:
  - `/etc/profile.d/panfrost.sh` → `export PAN_MESA_DEBUG=noafbc` (system-wide login shells)
  - `/etc/systemd/journald.conf.d/persistent.conf` → `Storage=persistent`, `SystemMaxUse=256M`, `SyncIntervalSec=1m`
  - `/etc/sysctl.d/99-panic-reboot.conf` → `kernel.panic=30`, `kernel.panic_on_oops=1`
  - `/boot/armbianEnv.txt` → `cma=256M` (down from failing 4096M)

**Verification:**
```bash
printenv PAN_MESA_DEBUG                # should be noafbc (in any session post-login)
journalctl --list-boots                # should show multiple entries after next reboot
grep CmaTotal /proc/meminfo            # should be non-zero (e.g. 262144 kB)
cat /proc/cmdline | grep cma           # should show cma=256M
sysctl kernel.panic                    # should be 30
```

**Rollback noafbc:** `rm ~/.config/environment.d/panfrost.conf && sed -i '/PAN_MESA_DEBUG/d' ~/.bashrc && sudo rm /etc/profile.d/panfrost.sh`

### 2026-08-28: HDMI switcher caused display + wifi failure (not a driver regression)

**Symptom:** Board was running fine at 1600x900. After a reboot, display was capped at 1024x768 and wifi was gone entirely. No config had been touched between the good and bad boots. A separate Raspberry Pi plugged into the same HDMI chain showed the identical 1024x768 symptom, confirming it wasn't board- or OS-specific. Removing the external HDMI switcher from the chain immediately restored both 1600x900 and wifi.

**Root cause:** RF/EMI, not power or software. The switcher had its own independent power supply with no electrical connection to either board — the only shared channel was the HDMI cable itself. A flaky/poorly-shielded switcher radiates noise from the TMDS clock and its harmonics, which can land in the 2.4GHz ISM band. On boards where the wifi antenna sits close to the HDMI port, that's enough to knock wifi out. The same signal integrity mess plausibly caused the DDC/EDID read to fail on that boot, falling back to the 1024x768 VESA default (the standard "couldn't read real EDID" fallback).

Why it only showed up after a reboot with nothing changed: EDID/DDC is only freshly re-negotiated on a cold probe (boot/hotplug). A marginal switcher can hold a stable, already-negotiated link indefinitely and only reveal a glitch the next time something forces a fresh handshake.

**Fix:** Remove the HDMI switcher from the chain. If a switcher must be used, verify it doesn't reproduce this failure across multiple reboots before trusting it.

**Lesson for future debugging:** If display caps at 1024x768 and/or wifi disappears right after a reboot with no board-side config changes, suspect the HDMI switcher/cable (EMI or bad EDID negotiation) before chasing a kernel/driver regression — check by removing external HDMI hardware first. Reproducing the same symptom on a second, unrelated device through the same physical chain is strong evidence it's the shared hardware, not either machine.

### 2026-09-03: Post-reflash fix audit + HDMI-RX/APU kernel-branch finding

**Symptom:** Board was reflashed. Checked each documented fix individually rather than assuming
either "all gone" or "all present" — the actual state was mixed: `PAN_MESA_DEBUG=noafbc`
(`.bashrc`, `~/.config/environment.d/panfrost.conf`) and the three kernel/DTB/u-boot apt holds
had survived, but the mt6360-tcpc blacklist, `cma=256M swiotlb=262144` boot args,
`/etc/profile.d/panfrost.sh`, persistent journald config, and the panic-reboot sysctl were all
missing. The IRQ 116 storm (see 2026-06-27 entry) was reproducing again as a result.

GPU DVFS (the `mali_sram-supply` dtbo patch, gpu-acceleration.md Fix 1) needed **no** action —
16 OPP levels present, no devfreq registration error in dmesg. Whatever shipped in this flash's
`gpu-mali.dtbo` is already correct; don't reapply that patch blindly, check dmesg first.

**Fix applied:** all of the above (except the dtbo, which wasn't needed) are now in one script:
`scripts/apply-stability-fixes.sh`, idempotent, safe to run after any future reflash. Run with
`sudo bash scripts/apply-stability-fixes.sh` then reboot. Still run `scripts/hold-kernel.sh`
separately afterward (or first — order doesn't matter) since the holds are apt state, not files
this script can idempotently detect the same way.

**HDMI-RX / NPUSYS long-shot — findings (no kernel work attempted yet):**

Pulled the actual Armbian `armbian/build` config for the `genio` board family
(`config/sources/families/genio.conf` + `config/kernel/linux-genio-{edge,vendor}.config`) to
settle the open question in `docs/hdmi-rx-porting-plan.md` and `docs/feature-migration-plan.md`
about whether `CONFIG_MTK_HDMI_RX` / an APU Kconfig symbol even exist in the tree we build from:

- **`edge` branch** (what this board runs — mainline-aligned, currently kernel 7.2 upstream in
  Armbian's tree vs. our installed `6.19.8-edge-genio`): grepping the full kernel config fragment
  found **no** `MTK_HDMI_RX` or `MTK_APU*` symbols at all — only `CONFIG_PHY_MTK_HDMI=y`, which is
  the HDMI *output* PHY, unrelated. The driver source for HDMI-RX and APUSYS is not present in
  this tree. This isn't a Kconfig flip; it would be a real backport from another kernel.
- **`vendor` branch** (`KERNELSOURCE=https://git.launchpad.net/~canonical-kernel/ubuntu/+source/linux-mtk`,
  Canonical's 5.15-based fork, same one the old libmali/Ubuntu-BSP era used — see gpu-acceleration.md's
  Historical Reference): **both drivers already exist and are wired up** —
  `CONFIG_MTK_HDMI_RX=m`, `CONFIG_MTK_APU=m`, `CONFIG_MTK_APUSYS_SUPPORT=m`,
  `CONFIG_MTK_APUSYS_MDLA_SUPPORT=y`, `CONFIG_MTK_APUSYS_VPU=y`. This branch is already a supported
  build target for this board (the family's `case $BRANCH in edge|vendor)` block covers it) — but
  it's a full kernel switch away from the current mainline/Panfrost stack, not an add-on: no
  Panfrost (back to `libmali` blob + the Glamor EGL shim from the top of this file), a 5.15
  kernel, and unknown DT coverage for NIO 12L specifically (that vendor tree's DT support was
  built around the EVK, not this board — untested here).

**Net assessment:**
- **HDMI-RX is very likely a dead end regardless of kernel branch**, independent of the software
  question above: `docs/feature-migration-plan.md` already established the EVK's HDMI-RX path
  depends on ITE IT6510/IT6625 external bridge chips physically populated on the EVK PCB, which
  the NIO 12L does not have and has no HDMI-in port for. Driver support existing on the vendor
  kernel doesn't create hardware that isn't on this board.
- **APU/NPUSYS is more plausible** — the MDLA/VPU cores are on-die on the MT8395 (SoC-level, not
  dependent on EVK-only external chips), so no equivalent hardware objection applies. But getting
  it onto the kernel this board actually runs means porting the out-of-tree APUSYS driver from a
  5.15-based fork to a 7.x mainline tree — real driver work (mailbox/IOMMU/genpd/power-domain APIs
  have moved a lot across those kernel generations), not a config flag. Alternative is building the
  `vendor` branch outright for this board, but that discards Panfrost and every mainline-era
  stability fix in this file, and its DT was never validated against NIO 12L wiring.

No kernel build was attempted this pass — this was a scoping/recon step only, done by
sparse-cloning `armbian/build`'s `config/` tree (no board/root access needed for this part).

### 2026-09-11: IRQ 116 storm still firing despite blacklist file present — initramfs was stale

**Symptom:** User reported poor stability on the current run even though all documented fixes
(per the 2026-09-03 audit) were confirmed present on disk. Checked live dmesg/journalctl for
the current boot and found the exact IRQ 116 storm from the 2026-04-11/06-27 entries firing
~54 seconds after kernel start, module `tcpci_mt6360` autoloading and getting force-disabled by
the kernel, just as before — even though `/etc/modprobe.d/disable-mt6360-tcpc.conf` existed.

**Root cause:** `tcpci_mt6360.ko` is bundled directly inside `/boot/initrd.img-6.19.8-edge-genio`,
and that initramfs carries its **own frozen copy** of `/etc/modprobe.d` (used by udev during
early boot, before the real rootfs's `/etc/modprobe.d` is consulted at all). The blacklist file
was written 2026-09-03; the initramfs was last built 2026-08-28 — five days *before* the
blacklist existed. Writing the blacklist file alone does nothing until the initramfs is
regenerated to include it; `scripts/apply-stability-fixes.sh` (2026-09-03) wrote the file but
never rebuilt the initramfs, so the fix silently never took effect on this run.

**Fix applied:** `scripts/apply-stability-fixes.sh` now compares the blacklist file's mtime
against `/boot/initrd.img` (resolved via `uname -r`) and runs `update-initramfs -u -k $(uname -r)`
whenever the initramfs is older. This makes the check self-healing on every future run instead
of a one-time manual step.

**Lesson for future debugging:** A modprobe blacklist (or any `/etc` config consumed by udev
during early boot) is not actually "in effect" just because the file exists — check whether the
running initramfs is newer than the file. `[[ "$file" -nt "$initrd" ]]` in a bash script is
enough to catch this class of bug. Applies to any fix that touches early-boot module loading,
not just this one.

### 2026-09-12: Verified initramfs fix holds after reboot

**Context:** First reboot since `ff1b615` (initramfs-staleness self-heal in
`scripts/apply-stability-fixes.sh`, see 2026-09-11 entry above).

Checked live state at ~2 min uptime on `6.19.8-edge-genio`:

```bash
journalctl -k -b | grep -Ei "irq 116|nobody cared|mt6360-tcpc"   # empty
lsmod | grep tcpci_mt6360                                        # not loaded
ls -la /boot/initrd.img-$(uname -r) /etc/modprobe.d/disable-mt6360-tcpc.conf
  # initrd.img rebuilt 2026-09-12 00:00, newer than the blacklist file (2026-09-03)
cat /proc/cmdline       # cma=256M swiotlb=262144 present
printenv PAN_MESA_DEBUG # noafbc
sysctl kernel.panic     # 30
```

**Result:** IRQ 116 storm and `tcpci_mt6360` load are both gone — the initramfs self-heal
worked as designed. `mt6360-regulator ... Failed to register 4 regulator` is still logged at
boot; that's the separate, already-documented LDO_VIN1/LDO_VIN3 supply-chain issue (2026-06-27
entry), unrelated to the storm, and expected to persist until the upstream DTS fix lands.

**Next test in progress:** user is opening multiple GPU-accelerated windows concurrently to
stress-test for the AFBC/Panfrost watchdog-reset failure mode from the 2026-06-28 entry
(hard lockup after ~4h uptime under sustained EGL/browser load). `noafbc` is confirmed set in
env for this session; watch for MTK WDT resets, `JOB_STATUS_INVALID_DATA_FAULT`, or a reboot
with no shutdown log during this test.

### 2026-09-13: Dev-tools audit + rescue kit set up on NX1TB

**Context:** User was compiling DSDA-Launcher and Dolphin locally (`~/Documents/dsda-launcher`,
`~/Documents/dolphin`) and wanted assurance that the board could compile "anything mainstream"
after a reflash. Separately, wanted a "rescue" folder — initially considered an SD card, but
moved to the NX1TB NVMe SSD (`/media/zach/NX1TB`, NTFS, 540G free vs. 201G free on the root
ext4 fs).

**Dev tools:** Core toolchain (gcc/clang, cmake, ninja, meson, autoconf/automake, Qt6 base,
node/npm) was already present. Cross-checked against Dolphin's actual upstream build-dep list
(`github.com/dolphin-emu/dolphin/wiki/Building-for-Linux`) and a general C/C++/Qt gap list;
installed 34 missing packages (SDL2 dev headers, libtool, gdb/valgrind/strace/ltrace, Qt6
Multimedia/Declarative/Wayland modules, libcubeb-dev, libgtest-dev, llvm-dev, etc. — full list
in git history for this file's commit). `libqt6opengl6-dev` was requested but doesn't exist as
a separate package anymore — `qt6-base-dev` now Breaks/Replaces it and pulls the OpenGL dev
headers in directly via `libopengl-dev`; not a failure. `libsdl3-dev` and `libminizip-ng-dev`
aren't in Ubuntu 24.04/noble's repos at all — Dolphin's CMake auto-vendors these from
`Externals/` when the system package is absent, so no action was needed there.

Also enabled `deb-src` in `/etc/apt/sources.list.d/ubuntu.sources` (deb822 format: added
`deb-src` to the `Types:` line) so `sudo apt build-dep <package>` works generically against
Ubuntu universe/multiverse going forward. Left `armbian.sources` deb-only since Armbian's own
packages aren't the "mainstream open-source project" case this was for. Verified working via
`apt-get build-dep --simulate vlc`.

**Rescue kit:** Note — NX1TB already had an unrelated "rescue" convention in
`NX1TB/files/` (rsync logs + corrupted-file lists from recovering photos/video off a failing
SD card, dated 2026-09-08). Confirmed with user this new folder is a *board* rescue kit, not
a continuation of that file-recovery work, before creating anything.

Built `/media/zach/NX1TB/rescue/`:
- `repo-snapshot/radxa-nio-12l-2026-09-13.tar.gz` — full tarball of this repo incl. `.git`.
- `boot-config/armbianEnv.txt.2026-09-13` — known-working boot args.
- `package-manifest/` — `kernel-state`, `apt-holds`, `manual-packages` (for
  `apt install $(cat ...)` reinstall), and `dpkg-selections`, all dated 2026-09-13.
- `README.md` explaining the above and why everything is a flat file/archive rather than an
  extracted tree.

**Rationale for flat files, not a live tree:** NX1TB is NTFS (`ntfs-3g`/fuseblk,
`user_id=0,group_id=0` per mount options) — it cannot preserve Unix permissions, ownership,
symlinks, or device/socket nodes. A raw extracted rootfs backup would silently lose that
metadata. Archives (`tar.gz`) and plain text manifests round-trip through NTFS perfectly since
the permission/symlink metadata lives inside the archive format itself, not the filesystem.
Applies to anything else added to this kit later.

**Known gap:** No kernel `.deb` files are backed up — `/var/cache/apt/archives` was already
empty when this kit was built (Armbian doesn't retain them by default). If a future reflash
lands on a different default kernel than `kernel-state-2026-09-13.txt` records, don't hunt for
the old `.deb`s — re-check `docs/gpu-acceleration.md` and re-run `apply-stability-fixes.sh` /
`hold-kernel.sh` from the extracted repo snapshot instead.

**Maintenance:** Nothing in the rescue kit auto-refreshes. Re-run the capture commands (see
`package-manifest/` file contents for the exact commands used) after the next stability fix,
kernel rebuild, or board-config change so the manifests don't drift from what's actually
running.
