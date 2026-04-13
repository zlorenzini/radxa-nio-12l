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
sudo sed -i 's#^extraargs=.*#extraargs=cma=512M swiotlb=262144#' /boot/armbianEnv.txt
sudo reboot
```

If `extraargs=` does not exist, append it:

```bash
echo 'extraargs=cma=512M swiotlb=262144' | sudo tee -a /boot/armbianEnv.txt
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
