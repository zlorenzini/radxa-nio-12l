# Hardware Reference — Radxa NIO 12L

## SoC: MediaTek MT8395 (Genio 1200)

- **CPU:** 4× Arm Cortex-A78 (performance) + 4× Arm Cortex-A55 (efficiency)
  - Big cores up to ~2.6 GHz; little cores up to ~2.0 GHz
- **GPU:** Mali-G57 MC5 (5-core)
  - No publicly available open-source driver for the full 3D stack
  - Userspace driver (`libmali`) required for OpenGL ES / Vulkan acceleration (see [`gpu-acceleration.md`](gpu-acceleration.md))
- **VPU:** Integrated HW codec (H.264, H.265, VP9); kernel driver present but userspace support varies by image
- **ISP:** Dual-ISP (MIPI CSI cameras), not used in this project yet
- **NPU:** MT3620 (6 TOPS); accessible via MediaTek NeuroPilot SDK (not yet configured)

---

## Memory & Storage

| Component | Spec |
|-----------|------|
| RAM | 16 GB LPDDR4X (dual-channel, soldered) |
| Storage | 256 GB UFS 2.1 (soldered) |
| Boot media | UFS only — no SD card on NIO 12L |

> **Note:** There are 8 GB RAM variants. The firmware `fip.bin` and `u-boot-initial-env` files are DDR-variant-specific — the 16 GB board requires the `ddr16g` files. Using the wrong variant causes silent hangs or boot loops. See [`flashing-ubuntu.md`](flashing-ubuntu.md).

---

## Ports & Connectivity

| Port | Details |
|------|---------|
| USB-C (right, OTG/power) | USB 3.1 Gen 1, also accepts PD charging (27 W tested), used for `genio-flash` download mode |
| USB-A ×3 | USB 3.0 (left bank); USB 2.0 (right bank) |
| HDMI | HDMI 2.0, up to 4K@60 |
| GbE | RJ-45, standard RGMII PHY |
| M.2 E-key | Wi-Fi / BT module slot |
| MIPI CSI | 2× camera connectors |
| GPIO / UART | 40-pin header (Raspberry Pi compatible pinout) |
| 3.5 mm audio | Headphone/microphone combo |

---

## Power Requirements

**Minimum: 5 V / 3 A (15 W). Recommended: 5 V / 5 A (25 W).**

> **PD is not supported.** The board draws straight 5 V — it does not negotiate USB Power Delivery. Use a supply that guarantees 3 A (or more) on the 5 V rail regardless of PD negotiation. A USB-A block rated 5 V / 3 A with a USB-C-to-A cable works correctly. A standard laptop USB-C port (~0.9 A) will power the board but cause instability and boot loops under load.

- Power input: right USB-C port
- Data (for flashing / ADB): left USB-A → board left USB-A (or any USB 3.0 port)
- Both ports can be connected simultaneously; the board draws power preferentially from the right port

---

## Thermal

The SoC and RAM chips run hot with no cooling:

| Sensor | Idle (no heatsink) | Idle (with heatsink) |
|--------|--------------------|----------------------|
| CPU / SoC | ~68–72 °C | ~62–66 °C |
| RAM (×2 chips) | ~65 °C estimated | ~60–63 °C |

**Heatsinks strongly recommended.** The board has no integrated heatsink mounting holes; small adhesive heatsinks on the SoC and both RAM packages work well. Use thermal compound or quality thermal tape.

Monitor temperature:
```bash
# On the board
cat /sys/class/thermal/thermal_zone*/temp   # raw millidegrees
# Or via MOTD on login (Ubuntu shows "Temperature: XX.X C")
```

---

## LED Indicators

| LED | Meaning |
|-----|---------|
| Green (PWR) | System powered on |
| Green (flash) | Download mode active / genio-flash transferring |

---

## Download Mode (for flashing)

1. Press and **hold** the Download button (small button on board edge, near USB-C OTG port)
2. Connect USB-C OTG to the host machine
3. **Release** the button
4. The host should enumerate a MediaTek USB device (`0e8d:201c` or `0e8d:0003`)

> The download mode connection is the right USB-C (OTG) port. Do not confuse it with a standard PD power port.

---

## udev Rules (on flashing host)

Create `/etc/udev/rules.d/72-aiot.rules` to allow non-root fastboot access:
```
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="201c", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="0003", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666", GROUP="plugdev"
```

Apply without reboot: `sudo udevadm control --reload-rules && sudo udevadm trigger`
