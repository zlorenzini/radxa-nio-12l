# HDMI RX Porting Plan - Radxa NIO 12L (Armbian 6.19)

## Goal

Enable stable HDMI input on NIO 12L while keeping the current NIO-oriented Armbian stack.

Success criteria:
- `modprobe mtk_hdmirx` succeeds.
- V4L2 capture node appears (expected naming may vary by kernel).
- HDMI audio capture source appears (`arecord -L` contains `hdmi_rx` or equivalent).
- Basic video preview and short audio/video recording pass.

---

## Why this approach

Use NIO 12L as the base platform and port HDMI RX support into the existing kernel/device tree flow, rather than trying to run the EVK image as-is.

Rationale:
- NIO and EVK share SoC family, but board wiring and boot assets differ.
- NIO board support is already validated for display, power, DDR variant, and general stability.
- Limiting change scope to HDMI RX reduces regressions.

---

## Baseline facts (already verified)

- Running kernel is `6.19.0-rc5-edge-genio`.
- `CONFIG_MTK_HDMI_RX` is absent in the running kernel config.
- `mtk_hdmirx` module is not present under `/lib/modules/6.19.0-rc5-edge-genio`.
- EVK image contains HDMI RX support in kernel/module and DTB layers.

Reference files in this repo:
- `kernel/userpatches/config/kernel/linux-genio-edge.config`
- `genio-g1200-evk-boot-assets-20250926-1185/u-boot-initial-env`
- `docs/flashing-armbian.md`
- `docs/flashing-ubuntu.md`

---

## Phase 1 - Kernel config enablement

Objective: make HDMI RX selectable/buildable in the NIO kernel.

Tasks:
1. Update edge kernel config to enable HDMI RX:
   - Add `CONFIG_MTK_HDMI_RX=m` (prefer module first for faster iteration).
2. Rebuild kernel/modules using your Armbian build flow.
3. Install and boot rebuilt kernel.

Validation:
- `grep -E '^CONFIG_MTK_HDMI_RX=' /boot/config-$(uname -r)` returns `m` or `y`.
- `find /lib/modules/$(uname -r) -type f | grep -E 'mtk_hdmirx\.ko(\.zst)?$'` finds the module.
- `sudo modprobe mtk_hdmirx` no longer fails with module-not-found.

Gate:
- Stop and investigate if symbol is missing from Kconfig on 6.19 (driver may require backport).

---

## Phase 2 - Driver source and compatibility

Objective: ensure the HDMI RX driver actually builds and loads on this kernel branch.

Tasks:
1. If Kconfig symbol exists and build works, continue.
2. If symbol does not exist or fails to build:
   - Pull HDMI RX driver sources from the nearest MediaTek branch known-good for MT8395.
   - Port minimal required interfaces to 6.19 (clock, media/v4l2, power domain API changes as needed).
3. Keep patch scope minimal and isolated.

Validation:
- Kernel build completes.
- `modprobe mtk_hdmirx` succeeds.
- `dmesg | grep -Ei 'hdmirx|mtk_hdmirx'` shows probe success, no fatal errors.

Gate:
- If probe fails with missing clocks/regulators/pinctrl, move to Phase 3 (DT alignment).

---

## Phase 3 - Device tree alignment for NIO 12L

Objective: align NIO DT with required HDMI RX node/pins/regulators.

Tasks:
1. Compare EVK HDMI RX DTS sections with NIO board DTS.
2. Port only HDMI RX-relevant pieces:
   - `hdmirx@...` node status and compatible.
   - required clocks and power-domain references.
   - pinctrl for HPD/5V/SCL/SDA as applicable.
   - supplies/regulators used by HDMI RX block.
3. Keep NIO-specific display and unrelated peripherals untouched.

Validation:
- `dmesg` shows successful probe and no deferred-probe loop.
- `ls /sys/firmware/devicetree/base | grep -i hdmirx` confirms node present.
- No regressions in existing HDMI output path.

Gate:
- If DT compiles but runtime probe fails, inspect regulator and clock trees first.

---

## Phase 4 - Capture pipeline verification

Objective: verify video capture and audio ingest paths are functioning.

Tasks:
1. Enumerate media devices:
   - `v4l2-ctl --list-devices`
   - `media-ctl -p` (if available)
2. Confirm audio source:
   - `arecord -L | grep -i hdmi`
3. Test preview:
   - `gst-launch-1.0 -v v4l2src device=/dev/videoX ! video/x-raw,width=1920,height=1080,format=YUY2 ! autovideosink`
4. Test short encode/mux capture once preview works.

Validation:
- Stable preview at expected resolution/framerate.
- Audio capture source is functional.
- 10-30 second recording succeeds.

Gate:
- If video works but audio does not, split ALSA routing debug from HDMI RX video driver debug.

---

## Phase 5 - Hardening and repo integration

Objective: make this reproducible for future flashes/builds.

Tasks:
1. Add a diagnostic script (example: `scripts/check-hdmirx.sh`) that runs:
   - module checks
   - probe log checks
   - device enumeration
   - optional one-shot capture test
2. Document the workflow and known caveats in docs.
3. Keep HDMI RX changes isolated in patches/config snippets for easy rebase.

Validation:
- Fresh flash + kernel install reproduces HDMI RX bring-up.
- Team member can follow docs without tribal knowledge.

---

## Risk register

- Mainline/vendor delta on 6.19 may require non-trivial driver backports.
- NIO board-level pin/regulator mappings may differ from EVK assumptions.
- Audio route may require additional ASoC machine/codec settings beyond HDMI RX core.
- Kernel upgrades may break forward-ported patches if not isolated cleanly.

---

## Recommended execution order (time-boxed)

Day 1:
1. Phase 1 complete or blocked with concrete error.
2. Start Phase 2 only if needed.

Days 2-3:
1. Phase 2 build/probe working.
2. Phase 3 DT bring-up to first successful probe.

Days 4-5:
1. Phase 4 preview/record validation.
2. Phase 5 scripts/docs cleanup.

---

## Quick command block

```bash
uname -r
grep -E '^CONFIG_MTK_HDMI_RX=' /boot/config-$(uname -r)
find /lib/modules/$(uname -r) -type f | grep -E 'mtk_hdmirx\.ko(\.zst)?$'
sudo modprobe mtk_hdmirx
sudo modprobe mtk-mdp3
dmesg | grep -Ei 'hdmirx|mtk_hdmirx|mdp|video'
v4l2-ctl --list-devices
arecord -L | grep -i hdmi
```

If these pass, proceed to GStreamer pipeline testing.
