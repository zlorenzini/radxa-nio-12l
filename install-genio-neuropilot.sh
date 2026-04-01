#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root, for example:"
    echo "  sudo ./install-genio-neuropilot.sh"
    exit 1
fi

if ! command -v apt-add-repository >/dev/null 2>&1; then
    apt update
    apt install -y software-properties-common
fi

echo "Adding Genio public PPA"
apt-add-repository -y ppa:mediatek-genio/genio-public

echo "Refreshing package index"
apt update

echo "Installing Genio 1200 APUSYS firmware package"
apt install -y mediatek-apusys-firmware-genio1200

echo "Installing NeuroPilot runtime packages"
apt install -y mediatek-libneuron mediatek-neuron-utils mediatek-libneuron-dev

echo "Installing Python runtime packages used by demos"
apt install -y python3-pip python3-numpy python3-pil

echo "Applying benchmark compatibility workaround"
mkdir -p /usr/share/benchmark_dla
if [[ -d /usr/share/neuropilot/benchmark_dla ]]; then
    cp -a /usr/share/neuropilot/benchmark_dla/. /usr/share/benchmark_dla/
fi

echo
echo "Installation completed. Reboot is required."
echo "Next steps:"
echo "  1) reboot"
echo "  2) sudo vpu5_test -a ks -l 10"
echo "  3) cd /home/radxa/repos/radxa-nio-12l && ./check-apu-env.sh"
echo "  4) cd /home/radxa/repos/radxa-nio-12l && ./run-apu-demo.sh"