# Embedded Development KB — Radxa NIO 12L

This document is the ongoing knowledge base for embedded device projects built on the NIO 12L. It covers system configuration, peripheral access, cross-compilation, deployment patterns, and project-specific notes.

---

## Board Identity

- **Hostname:** `mtk-genio`
- **SSH:** `ubuntu@192.168.0.155` (DHCP — check router if IP changes)
- **Password:** see secure storage (set during initial bring-up)
- **Kernel:** `5.15.0-1029-mtk` (MediaTek-patched Ubuntu kernel)
- **Distro:** Ubuntu 22.04.3 LTS

---

## GPIO / Hardware Interfaces

The NIO 12L exposes a 40-pin header with GPIO, UART, I2C, SPI, and PWM. It is electrically compatible with the Raspberry Pi 40-pin pinout but uses the MT8395 SoC's peripheral numbering.

### Accessing GPIO

```bash
# List available GPIO chips
gpiodetect

# Read a pin (chip 0, line N)
gpioget gpiochip0 <line>

# Set a pin high
gpioset gpiochip0 <line>=1
```

Install `gpiod` tools if not present:
```bash
sudo apt install gpiod
```

### UART

UART devices appear as `/dev/ttyS*` or `/dev/ttyMT*`. The debug UART is typically `/dev/ttyS0` at 921600 baud (kernel console) — do not use this for application serial unless you disable the kernel console first.

Application UARTs on the 40-pin header: TBD — map pins to `/dev/ttyS` numbers and document here.

### I2C

```bash
sudo apt install i2c-tools
ls /dev/i2c-*
sudo i2cdetect -l          # list all buses
sudo i2cdetect -y <bus>    # scan a bus for devices
```

### SPI

SPI devices appear as `/dev/spidev*`. Enable via device tree overlay if not present.

---

## Cross-Compilation Setup (from x86-64 host)

The board runs aarch64. To build natively on the board, use it directly (it is fast enough for most tasks). For build farm / CI use, cross-compile on an x86-64 host.

### Install aarch64 cross toolchain (Debian/Ubuntu host)
```bash
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
```

### CMake cross-compile example
```cmake
# toolchain-aarch64.cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
```
```bash
cmake -DCMAKE_TOOLCHAIN_FILE=toolchain-aarch64.cmake ..
```

### Deploying binaries
```bash
scp ./my-binary ubuntu@192.168.0.155:~/
ssh ubuntu@192.168.0.155 ./my-binary
```

---

## Systemd Service Template

For deploying an application as a persistent service:

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/home/ubuntu/myapp
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
```

---

## Headless Operation

To run without a monitor and without the desktop overhead:

```bash
sudo systemctl disable gdm3
sudo systemctl set-default multi-user.target
sudo reboot
```

This saves ~200 MB RAM and eliminates the gnome-shell CPU overhead. Re-enable with:
```bash
sudo systemctl enable gdm3
sudo systemctl set-default graphical.target
```

---

## Camera (MIPI CSI)

The board has two MIPI CSI-2 connectors. Camera support requires:
1. A compatible sensor module with the correct flex cable
2. A device tree overlay for the sensor
3. A V4L2 ISP pipeline or direct V4L2 access

Media pipeline:
```bash
sudo apt install v4l-utils
v4l2-ctl --list-devices
media-ctl --print-topology
```

Not yet configured — document sensor and overlay details here when a camera module is attached.

---

## NPU (Neural Processing Unit)

The MT8395 integrates a MediaTek APU (AI Processing Unit, marketed as 6 TOPS). Accessing it from Ubuntu requires:
- MediaTek's **NeuroPilot SDK** or **NeuroPilot Runtime**
- Model conversion to `.dla` (Deep Learning Accelerator) format

The NPU is not usable via standard frameworks (TensorFlow, PyTorch) without the NeuroPilot SDK. As a fallback, ONNX Runtime and TFLite can run inference via CPU/NEON with good performance on the A78 cores.

Links:
- MediaTek NeuroPilot: https://neuropilot.mediatek.com
- ONNX Runtime aarch64: `pip install onnxruntime`

---

## Networking

The board has a GbE port (onboard) and an M.2 E-key slot for Wi-Fi/BT.

### Static IP (if DHCP is unreliable)
Edit `/etc/netplan/` config:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses: [192.168.0.155/24]
      gateway4: 192.168.0.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```
```bash
sudo netplan apply
```

---

## USB OTG / Gadget Mode

The right USB-C port supports OTG / gadget mode (it is the MediaTek download port). In-kernel USB gadget drivers allow functions like:
- **USB serial** (`g_cdc` / `g_serial`)
- **USB network** (`g_ether` / RNDIS — this is what the board exposes during the flash sequence via `de:ad:be:ef:00:00`)
- **USB mass storage**

The RNDIS interface briefly appears during the genio-flash boot sequence. To use USB gadget networking persistently, configure `configfs` or use `systemd-networkd` with a gadget overlay.

During flashing from the host jumpstation, a udev rule auto-assigns `192.168.11.100/24` to `usb0` when the board's RNDIS MAC appears:
- Jumpstation: `/etc/udev/rules.d/73-rndis-nio12l.rules`

---

## Useful Kernel / System Diagnostics

```bash
# All thermal zones with names and temperatures
paste \
  <(cat /sys/class/thermal/thermal_zone*/type) \
  <(cat /sys/class/thermal/thermal_zone*/temp) | \
  awk '{printf "%-30s %.1f°C\n", $1, $2/1000}'

# CPU frequency scaling
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq

# DRM / display state
cat /sys/class/drm/card0-*/status

# USB devices
lsusb -t

# PCI/PCIe devices (M.2)
lspci 2>/dev/null || echo "no pciutils"

# Loaded kernel modules related to MTK peripherals
lsmod | grep -i mtk
```

---

## Project Log

| Date | Notes |
|------|-------|
| 2026-03-22 | Initial bring-up complete. Ubuntu 22.04 flashed, desktop working (Xorg + GNOME, software rendering). SSH stable. Heatsinks installed. |

---

## TODO / Future Work

- [ ] Mali-G57 `libmali` hardware acceleration
- [ ] Camera module bring-up (MIPI CSI)
- [ ] NPU / NeuroPilot SDK evaluation
- [ ] Android 11 image bring-up (image: `n12l_android11_20240912.zip`)
- [ ] USB gadget persistent networking
- [ ] Map 40-pin header GPIO/UART/SPI/I2C lines
- [ ] VPU hardware video decode (V4L2 M2M)
