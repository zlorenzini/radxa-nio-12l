#!/usr/bin/env bash

set -euo pipefail

SUPPORTED_CODENAME="jammy"

disable_invalid_genio_sources() {
    local changed=0

    for f in /etc/apt/sources.list.d/*mediatek-genio*; do
        [[ -e "$f" ]] || continue
        if grep -qiE "[[:space:]]noble[[:space:]]|Suites:[[:space:]]*noble" "$f"; then
            mv "$f" "${f}.disabled"
            echo "Disabled unsupported source: $f"
            changed=1
        fi
    done

    if [[ "$changed" -eq 1 ]]; then
        echo "Disabled unsupported Genio source entries for noble."
        echo "Run 'sudo apt update' to confirm apt is healthy again."
    fi
}

wait_for_apt_locks() {
    local waited=0
    local timeout=300

    echo "Waiting for apt/dpkg locks to be released (timeout: ${timeout}s)"
    while true; do
        local locked=0

        if command -v fuser >/dev/null 2>&1; then
            if fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; then
                locked=1
            fi
        else
            if pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1 || pgrep -x packagekitd >/dev/null 2>&1; then
                locked=1
            fi
        fi

        if [[ "$locked" -eq 0 ]]; then
            echo "apt/dpkg locks are free"
            return 0
        fi

        if [[ "$waited" -ge "$timeout" ]]; then
            echo "Timed out waiting for apt/dpkg locks. Try again in a minute." >&2
            return 1
        fi

        sleep 5
        waited=$((waited + 5))
    done
}

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root, for example:"
    echo "  sudo ./install-genio-neuropilot.sh"
    exit 1
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
else
    echo "Cannot read /etc/os-release" >&2
    exit 1
fi

CODENAME="${VERSION_CODENAME:-unknown}"
if [[ "$CODENAME" != "$SUPPORTED_CODENAME" ]]; then
    echo "Unsupported Ubuntu codename for this installer: $CODENAME" >&2
    echo "The MediaTek Genio PPA currently publishes packages for '$SUPPORTED_CODENAME' only." >&2
    disable_invalid_genio_sources
    echo "Use an Ubuntu on Genio image based on $SUPPORTED_CODENAME, then rerun this installer." >&2
    exit 2
fi

wait_for_apt_locks
if ! command -v apt-add-repository >/dev/null 2>&1; then
    apt update
    apt install -y software-properties-common
fi

echo "Adding Genio public PPA"
apt-add-repository -y -n ppa:mediatek-genio/genio-public

echo "Refreshing package index"
wait_for_apt_locks
apt update

echo "Installing Genio 1200 APUSYS firmware package"
wait_for_apt_locks
apt install -y mediatek-apusys-firmware-genio1200

echo "Installing NeuroPilot runtime packages"
wait_for_apt_locks
apt install -y mediatek-libneuron mediatek-neuron-utils mediatek-libneuron-dev

echo "Installing Python runtime packages used by demos"
wait_for_apt_locks
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