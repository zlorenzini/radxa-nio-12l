# USB Audio — Radxa NIO 12L

## Problem

The Armbian `6.19.0-rc5-edge-genio` image ships with `CONFIG_SND_USB_AUDIO` compiled out. USB audio devices are enumerated by the kernel (visible in `lsusb` and `dmesg`) but ALSA cannot attach a sound card to them — `/proc/asound/cards` shows only the onboard SOF device.

Confirmed on a C-Media CM108 USB PnP Sound Device:
```
# lsusb → sees the device
# cat /proc/asound/cards → only sof-mt8395-evk listed
# find /lib/modules/$(uname -r) -name 'snd-usb-audio*' → no output
```

There is no `linux-headers-edge-genio` package available, so the module cannot be built out-of-tree. A full kernel rebuild is required.

Note: `CONFIG_USB_AUDIO=m` (present in the base config) is the USB *gadget* audio function — it makes the board appear as a USB audio device to a connected host. It is unrelated to this fix.

---

## Fix: Build a Custom Kernel via Armbian Build Framework

The fix is a single Kconfig line: `CONFIG_SND_USB_AUDIO=m`. It is stored in this repo as a userpatches fragment and merged automatically by the Armbian build system on every rebuild.

**Fragment location (in this repo):**
```
kernel/userpatches/config/kernel/linux-genio-edge.config
```

### Prerequisites (jumpstation — one-time setup)

```bash
# Armbian build dependencies
sudo apt-get install -y git curl

# Build framework (already cloned to jumpdata)
# /mnt/jumpdata/armbian-build — already present
```

Verify the userpatches fragment is in place:
```bash
ls /mnt/jumpdata/armbian-build/userpatches/config/kernel/linux-genio-edge.config
```

If it's missing (e.g. after a fresh clone), copy it from this repo:
```bash
cp ~/jump/radxa-nio-12l/kernel/userpatches/config/kernel/linux-genio-edge.config \
   /mnt/jumpdata/armbian-build/userpatches/config/kernel/linux-genio-edge.config
```

### Build the Kernel

```bash
cd /mnt/jumpdata/armbian-build

sudo ./compile.sh \
  BOARD=radxa-nio-12l \
  BRANCH=edge \
  KERNEL_ONLY=yes \
  KERNEL_CONFIGURE=no \
  COMPRESS_OUTPUTIMAGE=no \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=yes
```

This takes ~30–60 minutes on the jumpstation (aarch64, 4 cores). Output `.deb` packages are written to `output/debs/`.

### Install on the Board

```bash
# Copy to board
scp /mnt/jumpdata/armbian-build/output/debs/linux-image-edge-genio_*.deb \
    radxa@192.168.0.77:~/ 

# Install
ssh radxa@192.168.0.77 "sudo dpkg -i ~/linux-image-edge-genio_*.deb"

# Hold — prevent apt from overwriting with the Armbian-distributed build
ssh radxa@192.168.0.77 "sudo apt-mark hold linux-image-edge-genio"

# Reboot
ssh radxa@192.168.0.77 "sudo reboot"
```

### Verify

After reboot:
```bash
ssh radxa@192.168.0.77 "
  # Module should now exist
  find /lib/modules/\$(uname -r) -name 'snd-usb-audio*'
  # Load it
  sudo modprobe snd-usb-audio
  # Should now show USB audio card alongside sof-mt8395-evk
  cat /proc/asound/cards
"
```

For auto-load on boot:
```bash
ssh radxa@192.168.0.77 "echo 'snd-usb-audio' | sudo tee /etc/modules-load.d/snd-usb-audio.conf"
```

---

## Updating the Kernel Later

When a new edge-genio release is worth taking:

1. Update the Armbian build repo:
   ```bash
   cd /mnt/jumpdata/armbian-build && git pull
   ```

2. Re-copy the fragment (in case `git pull` cleared `userpatches/`):
   ```bash
   cp ~/jump/radxa-nio-12l/kernel/userpatches/config/kernel/linux-genio-edge.config \
      /mnt/jumpdata/armbian-build/userpatches/config/kernel/linux-genio-edge.config
   ```

3. Rebuild with the same `compile.sh` command above.

4. Install the new `.deb` and re-hold the package.

The fragment never changes unless the Kconfig symbol is renamed in a future kernel — at which point update this doc and the fragment file together.
