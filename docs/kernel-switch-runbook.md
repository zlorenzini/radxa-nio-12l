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
- `/proc/cmdline` includes `cma=512M swiotlb=262144`
- No recurring DMA/IOMMU page-table allocation errors under video load

## 5) If cmdline parameters are missing

```bash
sudo sed -i 's#^extraargs=.*#extraargs=cma=512M swiotlb=262144#' /boot/armbianEnv.txt
sudo reboot
```

If `extraargs=` does not exist, append it:

```bash
echo 'extraargs=cma=512M swiotlb=262144' | sudo tee -a /boot/armbianEnv.txt
sudo reboot
```
