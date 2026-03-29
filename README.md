# Radxa NIO 12L — Setup Notes & Benchmarks

Documentation and notes for getting the **Radxa NIO 12L** single-board computer up and running on Armbian — covering hardware quirks, flashing, GPU bring-up, and benchmarks. Written against the 16 GB RAM / 256 GB UFS variant (kernel 6.19), but most of it applies to the 8 GB variant too.

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
| [`docs/flashing-armbian.md`](docs/flashing-armbian.md) | Flashing Armbian — image source, `genio-tools` procedure, RAM variant notes |
| [`docs/flashing-ubuntu.md`](docs/flashing-ubuntu.md) | Ubuntu flash procedure using `genio-tools` (historical reference) |
| [`docs/first-boot.md`](docs/first-boot.md) | Power requirements, boot loop pitfalls, SSH access |
| [`docs/display-troubleshooting.md`](docs/display-troubleshooting.md) | HDMI bring-up and troubleshooting (Ubuntu/Xorg history, still useful for Armbian) |
| [`docs/gpu-acceleration.md`](docs/gpu-acceleration.md) | Mali-G57 driver investigation; Panfrost vs. libmali history |
| [`docs/benchmarks.md`](docs/benchmarks.md) | GPU benchmark results — glmark2-es2-wayland score 2699, DVFS verification |
| [`docs/embedded-dev.md`](docs/embedded-dev.md) | Ongoing project notes |

---

## Quick-Start

### Need to flash first?
See [`docs/flashing-armbian.md`](docs/flashing-armbian.md). You'll need `genio-tools` installed on the host, and the correct DDR firmware variant (`ddr16g` for the 16 GB board).

### Already flashed

1. Connect monitor **before** powering on.
2. Power via a **5 V / 3 A minimum** supply on the right-side USB-C port (5 V / 5 A recommended). **PD is not supported** — use a supply that delivers 3 A on the 5 V rail unconditionally (a USB-A block + USB-C-to-A cable works perfectly).
3. Board boots to the Armbian first-run setup wizard (prompts for root password and creates a user).
4. SSH is available immediately: `ssh root@<board-ip>` until first-run setup completes.

---

## Scripts

| Script | Purpose |
|--------|---------|
| [`flash-ubuntu.sh`](flash-ubuntu.sh) | Ubuntu flash via `genio-flash` — historical reference; board currently runs Armbian |

---

## Status

- [x] Armbian (kernel 6.19) flashed and booting
- [x] SSH access
- [x] HDMI display
- [x] USB (all ports)
- [x] Wi-Fi
- [x] Mali-G57 GPU acceleration — Panfrost (open-source), Mesa 25.2.8, OpenGL ES 3.1; glmark2 score **2699** (see [`docs/benchmarks.md`](docs/benchmarks.md))
- [x] GPU DVFS — all 16 OPP levels (390–880 MHz) working after DT `mali_sram-supply` fix applied 2026-03-23
- [ ] Vulkan — no `panvk` ICD in Mesa 25.2 for Bifrost; upstream work in progress
- [ ] NPU (not yet tested)

---

## Known Gotchas

- **Power supply** — the board will boot-loop indefinitely on insufficient current (laptop USB-C at ~0.9 A is not enough). Use a dedicated 5 V / 3 A+ supply. See [`docs/first-boot.md`](docs/first-boot.md).
- **DDR variant** — there are 8 GB and 16 GB RAM variants. The firmware files in the image must match. The wrong variant causes boot loops. See [`docs/flashing-armbian.md`](docs/flashing-armbian.md).
- **GPU DVFS** — the stock `gpu-mali.dtbo` in some firmware versions has a mis-wired regulator reference for `mali_sram-supply` which locks the GPU at 390 MHz with no frequency scaling. See [`docs/gpu-acceleration.md`](docs/gpu-acceleration.md) for the fix.
- **Vulkan** — not available under Panfrost on Ubuntu 24.04's Mesa 25.2. Upstream `panvk` support for Bifrost is in development.

---

## Resources

- **Armbian for NIO 12L:** https://www.armbian.com/radxa-nio-12l/ — official image downloads and release notes
- **Radxa NIO 12L wiki:** https://wiki.radxa.com/Nio12L
- **MediaTek Genio 1200 (MT8395):** MT8395 is also sold as the Genio 1200; SoC docs and BSPs are interchangeable between the two names
