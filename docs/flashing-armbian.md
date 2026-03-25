# Flashing Armbian — Radxa NIO 12L

Armbian is the primary OS for the NIO 12L in this project. Images are maintained at:

**https://www.armbian.com/radxa-nio-12l/**

This page is the canonical source for Armbian releases for the NIO 12L — check it for updated images, release notes, and known issues. Images are updated independently of this repo; the link above will always point to the latest available build.

---

## Image Download

Download the latest image from the Armbian page above. Select the variant matching your use case (CLI vs. Desktop, mainline vs. vendor kernel).

**Current running image:** Armbian, kernel 6.19.

---

## Flashing Procedure

The NIO 12L uses MediaTek's `genio-tools` USB download protocol regardless of which OS image is being flashed. Host setup is identical to the Ubuntu procedure.

**Host setup:** Follow the prerequisites in [`flashing-ubuntu.md`](flashing-ubuntu.md) — the *Host Requirements*, *Python Environment*, and *udev Rules* sections apply unchanged.

### DDR Variant

The 16 GB board requires the `ddr16g` firmware variants (`fip.bin`, `u-boot-initial-env`). Verify these match before flashing — see [`flashing-ubuntu.md`](flashing-ubuntu.md) for details. Using the wrong variant causes silent hangs or boot loops.

### Flash

```bash
cd /path/to/armbian-image-directory
source /path/to/venv/bin/activate
genio-flash
```

Then enter Download Mode on the board:

1. Press and **hold** the Download button (small button near the USB-C OTG port)
2. Connect the board's USB-C OTG port to the host
3. **Release** the button

The green LED will pulse while `genio-flash` transfers partitions. The board reboots automatically on completion.

---

## First Boot

- **Power:** 5 V / 3 A minimum on the right-side USB-C port (5 V / 5 A recommended). PD is not supported — see [`hardware.md`](hardware.md#power-requirements).
- **Display:** Connect the monitor before powering on.
- **Credentials:** Armbian first-run setup prompts for root password and optional user creation on the serial console or over SSH on first login.
- **SSH:** Available immediately after boot on the DHCP-assigned IP. Default user is `root` until first-run setup completes.
