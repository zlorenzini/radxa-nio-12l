#!/usr/bin/env bash
# Flash Ubuntu to Radxa NIO 12L (16 GB DDR variant)
# Image: baoshan-classic-desktop-2204-x01-20231005-133-g1200-radxa-nio-12l-ufs-b9
#
# Full flashing guide: docs/flashing-ubuntu.md
#
# STEP 1: Run this script first — it waits for the board to appear.
# STEP 2: Enter Download Mode on the board:
#   a. Press and HOLD the Download button (small button near the USB-C OTG port)
#   b. Connect the board's USB-C OTG port to the host PC
#   c. RELEASE the Download button
#   The green LED will flash when genio-flash detects the board and begins.
#
# IMPORTANT — DDR variant:
#   The NIO 12L comes in 8 GB and 16 GB RAM variants. fip.bin and
#   u-boot-initial-env are variant-specific. This script verifies that
#   the files in the image directory match the ddr16g (16 GB) variants
#   before flashing. Using the wrong variant causes silent hangs/boot loops.
#
# IMPORTANT — Power:
#   Flash from the USB-A port on the left side of the jumpstation.
#   Power the board from a dedicated 27 W USB-C PSU on its right port.
#   Do not rely on a laptop USB port for power during or after flashing.

set -e

VENV="/home/zach/jump/radxa-nio-12l/venv"
IMAGE_DIR="/home/zach/jump/downloads/baoshan-classic-desktop-2204-x01-20231005-133-g1200-radxa-nio-12l-ufs-b9"

# Activate the genio-tools Python virtualenv.
# genio-tools must NOT be installed system-wide; it requires its own venv.
source "$VENV/bin/activate"

# Pre-flight: validate fastboot is available and udev rules are correct.
# Fails fast with a clear error if the host is not set up properly.
echo "=== genio-config check ==="
genio-config

echo ""
# Verify DDR variant files match the 16 GB board.
# The ddr16g and ddr8g fip.bin files are different — using ddr8g on a
# 16 GB board causes the board to hang silently after writing the
# initial bootloader stage.
echo "=== DDR variant check (must match ddr16g) ==="
FIP_BOARD=$(md5sum "$IMAGE_DIR/fip.bin" | cut -d' ' -f1)
FIP_16G=$(md5sum "$IMAGE_DIR/fip-ddr16g.bin" | cut -d' ' -f1)
if [ "$FIP_BOARD" != "$FIP_16G" ]; then
    echo "ERROR: fip.bin does not match fip-ddr16g.bin — wrong DDR variant!"
    echo "Fix: cp $IMAGE_DIR/fip-ddr16g.bin $IMAGE_DIR/fip.bin"
    exit 1
fi

ENV_BOARD=$(md5sum "$IMAGE_DIR/u-boot-initial-env" | cut -d' ' -f1)
ENV_16G=$(md5sum "$IMAGE_DIR/u-boot-initial-env-ddr16g" | cut -d' ' -f1)
if [ "$ENV_BOARD" != "$ENV_16G" ]; then
    echo "ERROR: u-boot-initial-env does not match u-boot-initial-env-ddr16g!"
    echo "Fix: cp $IMAGE_DIR/u-boot-initial-env-ddr16g $IMAGE_DIR/u-boot-initial-env"
    exit 1
fi

echo "fip.bin        OK  (ddr16g, md5: $FIP_BOARD)"
echo "u-boot-initial-env  OK  (ddr16g, md5: $ENV_BOARD)"

echo ""
echo "=== Starting genio-flash ==="
echo "Waiting for board in Download Mode..."
echo "  1. Hold Download button → connect USB-C OTG → release button"
echo ""

# genio-flash must be run from inside the image directory.
cd "$IMAGE_DIR"
genio-flash
