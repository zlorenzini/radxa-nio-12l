#!/usr/bin/env bash
# Pin the currently-installed kernel/DTB/u-boot so `apt upgrade` /
# `apt full-upgrade` / armbian-config's "Update" can't silently bump past
# the kernel version all the board's stability fixes are tuned for
# (mt6360-tcpc blacklist, cma=256M swiotlb=262144, PAN_MESA_DEBUG=noafbc,
# patched gpu-mali.dtbo regulator wiring — see AGENT-NOTES.md).
#
# Run with: sudo bash scripts/hold-kernel.sh

set -euo pipefail

PACKAGES=(
  linux-image-edge-genio
  linux-dtb-edge-genio
  linux-u-boot-radxa-nio-12l-edge
)

echo "Installed versions:"
dpkg -l "${PACKAGES[@]}" 2>/dev/null | awk '$1=="ii"{print "  " $2, $3}'

echo
echo "Holding: ${PACKAGES[*]}"
apt-mark hold "${PACKAGES[@]}"

echo
echo "Current holds:"
apt-mark showhold

echo
echo "Done. To later move to a new kernel intentionally:"
echo "  sudo apt-mark unhold ${PACKAGES[*]}"
echo "then follow docs/kernel-switch-runbook.md, and re-run this script once the new kernel is verified stable."
