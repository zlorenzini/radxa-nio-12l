# Flashing Ubuntu — Radxa NIO 12L

This guide covers flashing Ubuntu 22.04 to the NIO 12L using MediaTek's `genio-tools`. The process uses a custom USB download protocol — it is **not** a standard `dd` or `fastboot` flash.

---

## Prerequisites

### Host Requirements

Tested on: Debian bookworm (aarch64). Should work on any Ubuntu/Debian x86-64 or aarch64 host with Python 3.

```bash
sudo apt install python3 python3-pip python3-venv git \
     android-tools-fastboot adb
```

### Python Environment

`genio-tools` must be installed in a virtualenv — do not install system-wide.

```bash
python3 -m venv /path/to/your/venv
source /path/to/your/venv/bin/activate
pip install genio-tools==1.7.0
```

> **Version note:** 1.7.0 is the version verified to work with the `baoshan-classic-desktop` image series. Later versions may work but have not been tested here.

### udev Rules

Without these the tool fails with permission errors on the USB device.

Create `/etc/udev/rules.d/72-aiot.rules`:
```
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="201c", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="0003", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"
```

Create `/etc/udev/rules.d/96-rity.rules`:
```
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
```

Apply:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Verify your user is in the `plugdev` group:
```bash
groups $USER   # should include "plugdev"
# If not: sudo usermod -aG plugdev $USER && newgrp plugdev
```

---

## Image Selection

Download the latest `baoshan-classic-desktop` image for the NIO 12L from the Radxa downloads page. As of this writing the verified image is:

```
baoshan-classic-desktop-2204-x01-20231005-133-g1200-radxa-nio-12l-ufs-b9
```

The image ships with two DDR variant sets of `fip.bin` and `u-boot-initial-env`. **You must use the `ddr16g` variants for the 16 GB board.** The default files in the image root should already point to the correct variant, but verify:

```bash
cd /path/to/image
md5sum fip.bin fip-ddr16g.bin
# Both should match
md5sum u-boot-initial-env u-boot-initial-env-ddr16g
# Both should match
```

If they don't match, copy the correct variant over:
```bash
cp fip-ddr16g.bin fip.bin
cp u-boot-initial-env-ddr16g u-boot-initial-env
```

> Using the wrong DDR variant (`ddr8g`) on a 16 GB board causes the board to boot but immediately hang or reboot.

---

## Pre-flight Check

With the venv active, run `genio-config`. This validates fastboot is present and udev rules are correct:

```bash
source /path/to/venv/bin/activate
genio-config
```

Expected output (all green):
```
fastboot: OK
udev rules: OK
```

---

## Flashing

### 1. Start genio-flash (before connecting the board)

```bash
cd /path/to/image-directory
genio-flash
```

The tool will print something like:
```
Waiting for device in download mode...
```

### 2. Enter Download Mode on the board

1. Press and **hold** the Download button (small tactile button near the USB-C OTG port)
2. Connect the board's USB-C OTG port to a USB port on the host
3. **Release** the button

The green LED will pulse. `genio-flash` will detect the device and begin transferring partitions. This takes several minutes.

### 3. Wait for completion

The tool prints per-partition progress. Successful completion looks like:
```
...
Flashing completed successfully.
```
Exit code `0` = success.

The board will reboot automatically after flashing.

---

## Using the Convenience Script

[`flash-ubuntu.sh`](../flash-ubuntu.sh) in this repo handles venv activation, DDR variant verification, and launching `genio-flash` in one command:

```bash
bash flash-ubuntu.sh
```

Edit `VENV` and `IMAGE_DIR` at the top of the script to match your paths.

---

## Troubleshooting Flash Failures

### `genio-config` reports fastboot missing
```bash
sudo apt install android-tools-fastboot
```

### `genio-config` reports udev rules missing
Re-check the files in `/etc/udev/rules.d/` and reload:
```bash
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### Device not detected / no green LED
- Make sure you are using the **OTG USB-C port** (right side), not the USB-A ports
- Try a different USB cable — the download protocol requires a data-capable USB-C cable, not a charge-only cable
- Confirm you are holding the Download button before plugging in and releasing after

### Flash fails partway through
- Re-check DDR variant files match the board variant (see above)
- Power the board from a dedicated 27 W PSU rather than the host USB port during flashing
- Re-enter download mode and retry

### Board does not boot after flash
- See [`first-boot.md`](first-boot.md) — the most common cause is insufficient power
