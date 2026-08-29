# Kernel Switch Runbook (NIO 12L)

Use this when switching to a freshly built `edge-genio` kernel package set on the board.

## 1) Install packages built locally

```bash
cd /home/zach/Documents/build/output/debs
sudo dpkg -i \
  linux-image-edge-genio_26.05.0-trunk_arm64__1-Sd195-D0000-Pc5d4-C48a8-Hec90-HK01ba-Vc222-Bdc65-R448a.deb \
  linux-dtb-edge-genio_26.05.0-trunk_arm64__1-Sd195-D0000-Pc5d4-C48a8-Hec90-HK01ba-Vc222-Bdc65-R448a.deb
```

## 2) Hold kernel packages

```bash
sudo apt-mark hold linux-image-edge-genio linux-dtb-edge-genio
```

## 3) Reboot

```bash
sudo reboot
```

## 4) Post-reboot validation

```bash
uname -r
cat /proc/cmdline
dmesg | grep -Ei 'swiotlb|iommu|dma translation|buffer is full'
```

Expected:
- Running the newly installed edge-genio kernel
- IOMMU initializes in translated mode without recurring allocation failures
- No recurring DMA/IOMMU page-table allocation errors under video load

## 5) If DMA translation errors recur under load

Only apply this tuning if you observe errors such as:

```text
Cannot accommodate DMA translation for IOMMU page tables
swiotlb buffer is full
```

Then set larger DMA pools via boot args:

```bash
sudo sed -i 's#^extraargs=.*#extraargs=cma=4096M swiotlb=262144#' /boot/armbianEnv.txt
sudo reboot
```

If `extraargs=` does not exist, append it:

```bash
echo 'extraargs=cma=4096M swiotlb=262144' | sudo tee -a /boot/armbianEnv.txt
sudo reboot
```

## 6) Joystick / gamepad validation

After rebooting into a newly built kernel, verify controller input paths:

```bash
dmesg -T | grep -Ei 'usb|hid|xpad|sony|gamepad|joystick'
cat /proc/bus/input/devices
ls -l /dev/input/
```

Load classic joystick compatibility module (creates `/dev/input/js*` when supported):

```bash
sudo modprobe joydev
ls -l /dev/input/js*
```

If you get:

```text
modprobe: FATAL: Module joydev not found in directory /lib/modules/<kernel>
```

then the kernel was built without `CONFIG_INPUT_JOYDEV=m` (or `=y`).

This repo enables it in:

- `kernel/userpatches/config/kernel/linux-genio-edge.config`

Rebuild kernel packages and reinstall the new `linux-image-edge-genio` package.

## 7) Freezing on a known-good kernel (preventing unwanted upgrades)

The board carries a lot of version-specific state tied to the exact running kernel/DTB:
the `mt6360-tcpc` blacklist and IRQ 116 fix, the `cma=256M swiotlb=262144` boot args, the
`PAN_MESA_DEBUG=noafbc` AFBC workaround, and the patched `gpu-mali.dtbo` regulator wiring
(see `AGENT-NOTES.md`). None of these are guaranteed to still be needed — or to still work
the same way — on a different kernel build, and `apt.armbian.com` regularly carries a newer
`linux-image-edge-genio` candidate than what's installed.

Once a kernel is verified good, lock it down:

```bash
sudo bash scripts/hold-kernel.sh
```

which holds `linux-image-edge-genio`, `linux-dtb-edge-genio`, and
`linux-u-boot-radxa-nio-12l-edge`. This blocks `apt upgrade` / `apt full-upgrade` (and
armbian-config's "Update") from touching them. A `dpkg -i` of a new local build (step 1
above) still overrides a hold, so this runbook's own kernel-switch flow keeps working —
the hold only stops *automatic* upgrades.

Note: `unattended-upgrades` on this board only acts on origins matching
`${distro_id}:${distro_codename}` (i.e. `Ubuntu:noble`). Armbian's repo reports
`Origin: Armbian`, so it's already excluded from unattended-upgrades by default — the
hold above exists for manual/scripted `apt upgrade` runs, not unattended-upgrades. If that
ever changes (e.g. `Unattended-Upgrade::Allowed-Origins` gets a line added for Armbian, or
`Allow-Kernel-Update` is set), re-verify with:

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -iE "armbian|linux-image-edge-genio"
```

To later intentionally move to a new kernel, unhold first:

```bash
sudo apt-mark unhold linux-image-edge-genio linux-dtb-edge-genio linux-u-boot-radxa-nio-12l-edge
```

then follow this runbook from step 1, and re-run `scripts/hold-kernel.sh` once the new
kernel is verified stable.
