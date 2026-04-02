# Feature Migration Plan — Genio 1200 Armbian

Enable APU inference, USB audio, USB gadget (mass storage), and USB-based camera input on the
existing Armbian noble stack. The downloaded scarthgap Yocto image is used as a component donor
only — not as a flashing target.

Last updated: 2026-04-02

---

## Scope

| Feature | Target | Notes |
|---------|--------|-------|
| APU / NeuroPilot inference | Full functional parity | Requires one kernel rebuild + Yocto userspace extraction |
| USB audio devices (host) | Plug-and-play ALSA enumeration | Kernel already fixed; needs autoload + regression checks |
| USB gadget — mass storage | Persistent on boot | Pure userspace; no kernel rebuild needed |
| Camera input for live inference | UVC USB capture card | Replaces internal HDMI-RX path (see note below) |
| Internal MT8395 HDMI-RX block | Stretch / future research | See [hdmi-rx-porting-plan.md](hdmi-rx-porting-plan.md) |

**HDMI-RX note:** The Yocto scarthgap image's HDMI-RX support uses ITE IT6510/IT6625 external
bridge chips physically on the EVK PCB. The NIO 12L does not have those chips and has no
HDMI-in port. A UVC-compatible USB capture card is a drop-in V4L2 source that works under the
current kernel with zero porting work and is the practical path for live inference input.
Internal HDMI-RX remains a long-term research item tracked in
[hdmi-rx-porting-plan.md](hdmi-rx-porting-plan.md).

---

## Efficiency strategy

1. **One Yocto extraction pass.** Mount the scarthgap WIC image once and pull all needed
   artifacts in a single session: APU firmware, libs, config files. Do not re-mount repeatedly.

2. **One kernel rebuild.** All Kconfig changes across all features must be batched into the
   kernel fragment before triggering `compile.sh`. The rebuild takes ~60 min on the jumpstation —
   this must not happen more than once per iteration.

3. **Userspace first.** APU userspace staging and USB gadget setup require no kernel rebuild;
   they can be done on the board now and will be fully ready when the rebuilt kernel boots.

4. **Reuse existing validation harness.** `check-apu-env.sh` is the model — extend it rather
   than writing separate per-feature scripts.

---

## Phase 0 — Yocto extraction (one pass, blocks all APU work)

**Done on: board (needs sudo for loop mount)**

Extract all component-donor assets from the scarthgap WIC image in a single pass.

```bash
# Attach WIC image
sudo losetup --show -f -P .tmp-scarthgap-extract/scarthgap.raw.wic.img
# Example output: /dev/loop0

# Find the rootfs partition (usually the largest)
lsblk /dev/loop0

# Mount rootfs (adjust partition number as needed, typically p5 or similar)
sudo mount -o ro /dev/loop0pN .tmp-scarthgap-extract/mnt-rootfs/

# Extract APU runtime assets (see Phase 1 for destinations)
sudo find .tmp-scarthgap-extract/mnt-rootfs/ \
  \( -path '*/usr/sbin/ncc-tflite' \
  -o -path '*/usr/sbin/neuronrt' \
  -o -path '*/usr/sbin/runtime_api_sample' \
  -o -path '*/etc/apusys/mt8195/nhw' \
  -o -path '*/vendor/etc/armnn_app.config' \
  -o -path '*/usr/lib/firmware/mediatek/mt8395/apusys*' \
  -o -path '*/usr/lib/firmware/mediatek/mt8395/cam_vpu*' \
  -o -name 'libneuronusdk*' \
  -o -name 'libapu_mdw*' \
  -o -name 'libmdla_ut*' \
  -o -name 'libvpu5*' \
  -o -name 'libapusys_edma*' \) \
  -print 2>/dev/null

# Unmount when done; do not leave mounted
sudo umount .tmp-scarthgap-extract/mnt-rootfs/
sudo losetup -d /dev/loop0
```

> `.tmp-scarthgap-extract/` and its contents are gitignored. Keep extracted working copies there.

---

## Phase 1 — APU functional parity

**Requires:** Phase 0 extraction complete + one kernel rebuild (jumpstation).

### 1a. Kernel rebuild (jumpstation)

Add `CONFIG_MTK_APU_CORE` (and any dependent symbols identified during Phase 0 — check the
extracted Yocto kernel config at `.tmp-scarthgap-extract/mnt-rootfs/boot/config-*` for the
exact symbol names) to the existing fragment:

```
kernel/userpatches/config/kernel/linux-genio-edge.config
```

Also batch in the USB audio and gadget symbols at the same time (see Phase 2). Then on the
jumpstation:

```bash
# Sync this repo to jumpstation first (git push / rsync)
cp ~/jump/radxa-nio-12l/kernel/userpatches/config/kernel/linux-genio-edge.config \
   /mnt/jumpdata/armbian-build/userpatches/config/kernel/linux-genio-edge.config

cd /mnt/jumpdata/armbian-build
sudo ./compile.sh \
  BOARD=radxa-nio-12l \
  BRANCH=edge \
  KERNEL_ONLY=yes \
  KERNEL_CONFIGURE=no \
  COMPRESS_OUTPUTIMAGE=no \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=yes

# SCP result to board and install
scp output/debs/linux-image-edge-genio_*.deb radxa@<board-ip>:~/
ssh radxa@<board-ip> "sudo dpkg -i ~/linux-image-edge-genio_*.deb && sudo apt-mark hold linux-image-edge-genio && sudo reboot"
```

See [usb-audio.md](usb-audio.md) for the full annotated workflow.

### 1b. Userspace staging (board, no rebuild needed)

Copy APU runtime components from Phase 0 extraction to system paths:

```bash
# Tools (verify these exist in your Phase 0 extract first)
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/sbin/ncc-tflite /usr/sbin/
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/sbin/neuronrt /usr/sbin/
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/sbin/runtime_api_sample /usr/sbin/
sudo chmod +x /usr/sbin/{ncc-tflite,neuronrt,runtime_api_sample}

# Libraries — note Yocto uses /usr/lib64; Armbian uses /usr/lib
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/lib64/libneuronusdk*.so* /usr/lib/
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/lib64/libapu_mdw*.so* /usr/lib/
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/lib64/libmdla_ut*.so* /usr/lib/
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/lib64/libvpu5*.so* /usr/lib/
sudo cp .tmp-scarthgap-extract/mnt-rootfs/usr/lib64/libapusys_edma*.so* /usr/lib/
sudo ldconfig

# Config files
sudo mkdir -p /etc/apusys/mt8195
sudo cp .tmp-scarthgap-extract/mnt-rootfs/etc/apusys/mt8195/nhw /etc/apusys/mt8195/nhw
sudo ln -sf apusys/mt8195/nhw /etc/nhw

# armnn_app.config — if not found in scarthgap rootfs, check /vendor/etc/ or /etc/
# This file is proprietary; check under /usr/share, /etc, /vendor within the mounted rootfs
# sudo mkdir -p /vendor/etc
# sudo cp .tmp-scarthgap-extract/mnt-rootfs/vendor/etc/armnn_app.config /vendor/etc/

# Firmware — only if not already present
sudo mkdir -p /lib/firmware/mediatek/mt8395
for f in apusys.sig.img cam_vpu1.img cam_vpu2.img cam_vpu3.img; do
  [ -f "/lib/firmware/mediatek/mt8395/$f" ] || \
    sudo cp ".tmp-scarthgap-extract/mnt-rootfs/usr/lib/firmware/mediatek/mt8395/$f" \
            "/lib/firmware/mediatek/mt8395/$f"
done
```

### 1c. Validation

```bash
# Before kernel rebuild — checks all userspace layers
./check-apu-env.sh
# Expected after 1b: all userspace checks pass; device node WARNs are expected until new kernel

# After kernel rebuild + reboot
./check-apu-env.sh   # should reach 0 failures
./run-apu-demo.sh    # end-to-end inference smoke test
```

---

## Phase 2 — USB audio + USB gadget

### 2a. Kernel fragment additions (batch with Phase 1 rebuild)

Add to `kernel/userpatches/config/kernel/linux-genio-edge.config` before triggering the rebuild:

```
# USB audio host (plug-and-play ALSA for USB audio devices)
CONFIG_SND_USB_AUDIO=m

# USB gadget mass storage
CONFIG_USB_MASS_STORAGE=m
```

**Note:** `CONFIG_SND_USB_AUDIO=m` is already present in the fragment. Confirm before adding
a duplicate.

### 2b. USB audio autoload (board, no rebuild needed)

```bash
echo 'snd-usb-audio' | sudo tee /etc/modules-load.d/snd-usb-audio.conf

# Verify after next boot (or modprobe now)
sudo modprobe snd-usb-audio
cat /proc/asound/cards   # USB device should appear alongside sof-mt8395-evk
```

### 2c. USB gadget mass storage — persistent systemd unit

Create the gadget activation unit so it persists across boots. The right USB-C port (OTG) is
the gadget port. A backing file or block device must exist before activating.

```bash
# Create a backing image (adjust size as needed)
sudo dd if=/dev/zero of=/var/lib/usb-gadget-storage.img bs=1M count=512
sudo mkfs.vfat /var/lib/usb-gadget-storage.img

# Create the systemd unit
sudo tee /etc/systemd/system/usb-gadget-storage.service > /dev/null << 'EOF'
[Unit]
Description=USB Gadget — Mass Storage
After=local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes

ExecStart=/bin/bash -c '\
  modprobe libcomposite; \
  cd /sys/kernel/config/usb_gadget; \
  mkdir -p nio12l; cd nio12l; \
  echo 0x0525 > idVendor; echo 0xa4a5 > idProduct; \
  mkdir -p strings/0x409; \
  echo "RadxaNIO12L" > strings/0x409/manufacturer; \
  echo "NIO12L Storage" > strings/0x409/product; \
  mkdir -p configs/c.1/strings/0x409; \
  echo "Config 1" > configs/c.1/strings/0x409/configuration; \
  mkdir -p functions/mass_storage.0; \
  echo /var/lib/usb-gadget-storage.img > functions/mass_storage.0/lun.0/file; \
  echo 0 > functions/mass_storage.0/lun.0/removable; \
  ln -s functions/mass_storage.0 configs/c.1/; \
  ls /sys/class/udc | head -1 | xargs -I{} echo {} > UDC'

ExecStop=/bin/bash -c '\
  cd /sys/kernel/config/usb_gadget/nio12l 2>/dev/null || exit 0; \
  echo "" > UDC; \
  rm -f configs/c.1/mass_storage.0; \
  rmdir functions/mass_storage.0 configs/c.1/strings/0x409 configs/c.1 strings/0x409 2>/dev/null; \
  cd /sys/kernel/config/usb_gadget; rmdir nio12l 2>/dev/null; true'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable usb-gadget-storage.service
sudo systemctl start usb-gadget-storage.service

# Verify
ls /sys/kernel/config/usb_gadget/nio12l/
```

### 2d. Validation

```bash
# USB audio
cat /proc/asound/cards                  # USB device listed
aplay -l | grep -i usb                 # playback device visible
arecord -l | grep -i usb              # capture device visible (if mic present)

# USB gadget
systemctl status usb-gadget-storage.service
lsusb | grep -i storage               # from a connected host
# Host should see a USB mass storage device and mount it
```

---

## Phase 3 — USB capture card for live inference

No kernel changes required. Any UVC-compatible USB HDMI capture card (e.g. MACROSILICON MS2109,
Elgato Cam Link, generic "USB 3.0 Capture Card") enumerates as a standard V4L2 device.

### 3a. Verify enumeration

```bash
lsusb                                  # confirm capture card appears
v4l2-ctl --list-devices                # should show /dev/videoX for the UVC device
v4l2-ctl -d /dev/videoX --list-formats-ext  # check supported resolutions/framerates
```

### 3b. Test capture pipeline

```bash
# Install GStreamer if not present
sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-good \
                        gstreamer1.0-plugins-bad python3-gi

# Preview (replace videoX with actual device)
gst-launch-1.0 v4l2src device=/dev/videoX ! videoconvert ! autovideosink

# Headless frame grab for inference testing
gst-launch-1.0 v4l2src device=/dev/videoX num-buffers=1 ! \
  videoconvert ! video/x-raw,format=BGR ! \
  filesink location=/tmp/test-frame.bgr
```

### 3c. Live inference integration with APU

Once Phase 1 APU is working and Phase 3 capture is verified, wire them together.
The NeuroPilot runtime accepts pre-processed input buffers — the integration point is feeding
V4L2 frames through a preprocessing step (resize + normalize to model input dims) before passing
to `neuronrt` or `runtime_api_sample`.

Reference starting point:
```bash
# Verify APU accepts inference on a sample input
./run-apu-demo.sh

# Then replace the static sample image with a captured V4L2 frame
# (preprocessing pipeline to be defined based on target model input shape)
```

---

## Phase 4 — Integration and hardening

Once Phases 1–3 pass independently:

1. Run full regression: cold boot, warm reboot, reflash + restore.
2. Confirm `apt-mark hold linux-image-edge-genio` is in place (prevents auto-update breaking
   the APU kernel module).
3. Extend `check-apu-env.sh` to also check USB audio module presence and gadget service state.
4. Commit final kernel fragment, systemd unit, and any install scripts to repo.
5. Update `AGENT-NOTES.md` with lessons learned.

---

## Kernel fragment — current state

Location: `kernel/userpatches/config/kernel/linux-genio-edge.config`

Symbols confirmed needed for this plan (batch all into one rebuild):

| Symbol | Purpose | Status |
|--------|---------|--------|
| `CONFIG_SND_USB_AUDIO=m` | USB audio host | Already in fragment |
| `CONFIG_MTK_APU_CORE=m` | APUSYS driver | **Needs adding — verify exact symbol name from extracted Yocto kernel config** |
| `CONFIG_USB_MASS_STORAGE=m` | USB gadget mass storage | **Needs adding** |

**Verify Yocto symbol names before adding:**
```bash
# After Phase 0 mount — check what Yocto actually uses
grep -E 'APUSYS|APU_CORE|MDLA|MTK_APU' \
  .tmp-scarthgap-extract/mnt-rootfs/boot/config-* 2>/dev/null | sort -u
```

---

## Jump station sync

Before running the rebuild on the jumpstation, sync the repo:

```bash
# From this machine
git push

# On jumpstation
cd ~/jump/radxa-nio-12l && git pull
cp kernel/userpatches/config/kernel/linux-genio-edge.config \
   /mnt/jumpdata/armbian-build/userpatches/config/kernel/linux-genio-edge.config
```

---

## Known constraints

- `linux-headers-edge-genio` is not packaged — out-of-tree modules cannot be built on the board.
  All kernel changes must go through the Armbian `compile.sh` flow on the jumpstation.
- The `mediatek-genio/genio-public` PPA only publishes `jammy` packages; it does not work on
  Armbian noble. All APU components must come from the Yocto extraction.
- The APUSYS driver is an out-of-tree module in Yocto (`kernel-module-apusys`). Its exact
  Kconfig symbol on Armbian 6.19 must be verified from the extracted Yocto kernel config before
  adding to the fragment.
- Firmware files (`fip.bin`, `u-boot-initial-env`) are DDR-variant-specific. This board is
  16 GB — always use `ddr16g` variants when reflashing.
