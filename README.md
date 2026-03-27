# Radxa NIO 12L — Knowledge Base

This repository is the operational knowledge base for the **Radxa NIO 12L** single-board computer — specifically the 16 GB DDR / 256 GB UFS variant, currently running Armbian with kernel 6.19.

---

## Hardware at a Glance

| Attribute | Value |
|-----------|-------|
| SoC | MediaTek MT8395 (Genio 1200) |
| CPU | 4× Cortex-A78 + 4× Cortex-A55 @ up to 2.6 GHz |
| GPU | Mali-G57 MC5 |
| RAM | 16 GB LPDDR4X |
| Storage | 256 GB UFS |
| OS | Armbian (kernel 6.19) |

Full hardware details → [`docs/hardware.md`](docs/hardware.md)

---

## Contents

| Document | What it covers |
|----------|---------------|
| [`docs/hardware.md`](docs/hardware.md) | Board layout, ports, power requirements, thermal notes |
| [`docs/flashing-armbian.md`](docs/flashing-armbian.md) | Flashing Armbian — image source, genio-tools procedure, DDR variant notes |
| [`docs/flashing-ubuntu.md`](docs/flashing-ubuntu.md) | Ubuntu flash procedure using `genio-tools` (historical reference) |
| [`docs/first-boot.md`](docs/first-boot.md) | Power requirements, boot loop pitfalls, SSH access — Ubuntu context, but power/connectivity notes still apply |
| [`docs/display-troubleshooting.md`](docs/display-troubleshooting.md) | Full root-cause chain for the HDMI black screen (Ubuntu/Xorg history) |
| [`docs/gpu-acceleration.md`](docs/gpu-acceleration.md) | Mali-G57 driver investigation; libmali bring-up history |
| [`docs/usb-audio.md`](docs/usb-audio.md) | USB audio kernel rebuild — `CONFIG_SND_USB_AUDIO` missing from Armbian image; fix + update process |
| [`docs/embedded-dev.md`](docs/embedded-dev.md) | Embedded device KB — ongoing notes for projects based on this board |

---

## Quick-Start (already flashed)

1. Connect monitor **before** powering on.
2. Power via a **5 V / 3 A minimum** supply on the right-side USB-C port (5 V / 5 A recommended). PD is not supported — use a supply that guarantees 3 A on the 5 V rail.
3. Board boots to login. Credentials set during Armbian first-run setup.
4. SSH: `ssh <user>@<board-ip>` (see [`docs/embedded-dev.md`](docs/embedded-dev.md) for current IP and user).

---

## Scripts

| Script | Purpose |
|--------|---------|
| [`flash-ubuntu.sh`](flash-ubuntu.sh) | Ubuntu flash via `genio-flash` (historical — board now runs Armbian) |

---

## Status

- [x] Armbian (kernel 6.19) flashed and booting
- [x] SSH access
- [x] HDMI display
- [x] USB (all ports)
- [x] Wi-Fi
- [x] Mali-G57 GPU acceleration
- [ ] USB audio (`snd-usb-audio` — kernel rebuild in progress; see [`docs/usb-audio.md`](docs/usb-audio.md))
- [ ] NPU (not yet tested)

---

## Resources

- **Armbian for NIO 12L:** https://www.armbian.com/radxa-nio-12l/ — official image downloads and release notes; check here for updates
