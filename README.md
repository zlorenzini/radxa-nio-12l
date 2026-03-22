# Radxa NIO 12L — Knowledge Base

This repository is the operational knowledge base for the **Radxa NIO 12L** (Network I/O, 12-core, Lite) single-board computer — specifically the 16 GB DDR / 256 GB UFS variant. It covers initial setup, Ubuntu flashing, display bring-up, and ongoing embedded development notes.

---

## Hardware at a Glance

| Attribute | Value |
|-----------|-------|
| SoC | MediaTek MT8395 (Genio 1200) |
| CPU | 4× Cortex-A78 + 4× Cortex-A55 @ up to 2.6 GHz |
| GPU | Mali-G57 MC5 |
| RAM | 16 GB LPDDR4X |
| Storage | 256 GB UFS |
| OS used | Ubuntu 22.04.3 LTS (kernel `5.15.0-1029-mtk`) |

Full hardware details → [`docs/hardware.md`](docs/hardware.md)

---

## Contents

| Document | What it covers |
|----------|---------------|
| [`docs/hardware.md`](docs/hardware.md) | Board layout, ports, power requirements, thermal notes |
| [`docs/flashing-ubuntu.md`](docs/flashing-ubuntu.md) | End-to-end Ubuntu flash using `genio-tools` |
| [`docs/first-boot.md`](docs/first-boot.md) | Power, boot loop pitfalls, SSH access, GDM crash loop |
| [`docs/display-troubleshooting.md`](docs/display-troubleshooting.md) | Full root-cause chain for the HDMI black screen; working config |
| [`docs/gpu-acceleration.md`](docs/gpu-acceleration.md) | Mali-G57 driver situation; software rendering workaround; upgrade path |
| [`docs/embedded-dev.md`](docs/embedded-dev.md) | Embedded device KB — ongoing notes for projects based on this board |

---

## Quick-Start (already flashed)

1. Connect monitor **before** powering on (Xorg reads EDID at init time).
2. Power via **27 W USB-C PSU** on the right-side port.
3. Board boots to GDM login. Log in as `ubuntu`.
4. SSH: `ssh ubuntu@<board-ip>` (default credentials set during flash; see [`docs/first-boot.md`](docs/first-boot.md)).

---

## Scripts

| Script | Purpose |
|--------|---------|
| [`flash-ubuntu.sh`](flash-ubuntu.sh) | Activate venv, run pre-flight checks, launch `genio-flash` |

---

## Status

- [x] Ubuntu 22.04 flashed and booting
- [x] SSH access
- [x] HDMI desktop (Xorg + GNOME, software rendering)
- [ ] Mali-G57 hardware acceleration
- [ ] Android image bring-up
