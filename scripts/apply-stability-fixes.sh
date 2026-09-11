#!/usr/bin/env bash
# Reapply the post-flash stability fixes documented in AGENT-NOTES.md.
#
# These fixes do not survive a reflash (and, per 2026-09-03, apparently not
# every "reflash" either -- some of them turned up already in place while
# others were missing, so this script is written to be idempotent and safe
# to run on any boot state rather than assuming a truly blank system).
#
# Covers:
#   1. mt6360-tcpc IRQ 116 storm -- blacklist tcpci_mt6360 (2026-06-27 fix)
#   2. DMA/IOMMU headroom -- cma=256M swiotlb=262144 boot args (2026-06-27/28)
#   3. Panfrost AFBC corruption -- PAN_MESA_DEBUG=noafbc, system-wide (2026-06-28)
#   4. Persistent journal -- survive crashes for postmortem (2026-06-28)
#   5. Panic-on-oops + reboot -- avoid silent hangs (2026-06-28)
#   6. Kernel/DTB/u-boot apt holds -- see scripts/hold-kernel.sh (not duplicated here)
#
# Does NOT touch the gpu-mali.dtbo mali_sram-supply patch (docs/gpu-acceleration.md
# Fix 1) -- verify first with the check below; only patch if actually broken.
#
# Run with: sudo bash scripts/apply-stability-fixes.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

changed=0

echo "== 1. mt6360-tcpc IRQ 116 storm =="
BLACKLIST=/etc/modprobe.d/disable-mt6360-tcpc.conf
if [[ -f "$BLACKLIST" ]]; then
    echo "  already blacklisted ($BLACKLIST)"
else
    echo "blacklist tcpci_mt6360" > "$BLACKLIST"
    echo "  wrote $BLACKLIST"
    changed=1
fi
if lsmod | grep -q '^tcpci_mt6360'; then
    modprobe -r tcpci_mt6360 2>/dev/null && echo "  unloaded tcpci_mt6360 (was loaded this boot)" \
        || echo "  WARNING: tcpci_mt6360 loaded and busy; reboot to fully clear it"
fi

echo "== 2. DMA/IOMMU boot args (cma=256M swiotlb=262144) =="
ENVFILE=/boot/armbianEnv.txt
if grep -q 'cma=256M' "$ENVFILE" 2>/dev/null; then
    echo "  already present in $ENVFILE"
elif grep -q '^extraargs=' "$ENVFILE" 2>/dev/null; then
    sed -i 's/^extraargs=.*/extraargs=cma=256M swiotlb=262144/' "$ENVFILE"
    echo "  updated existing extraargs= line in $ENVFILE"
    changed=1
else
    echo 'extraargs=cma=256M swiotlb=262144' >> "$ENVFILE"
    echo "  appended extraargs= line to $ENVFILE"
    changed=1
fi

echo "== 3. Panfrost AFBC fix (PAN_MESA_DEBUG=noafbc), system-wide =="
PROFILE_D=/etc/profile.d/panfrost.sh
if [[ -f "$PROFILE_D" ]] && grep -q 'PAN_MESA_DEBUG=noafbc' "$PROFILE_D"; then
    echo "  already present ($PROFILE_D)"
else
    echo 'export PAN_MESA_DEBUG=noafbc' > "$PROFILE_D"
    echo "  wrote $PROFILE_D"
    changed=1
fi
# Also cover the invoking user's session directly (systemd user env + interactive shells),
# in case only the system-wide file was missing.
if [[ -n "$REAL_HOME" && -d "$REAL_HOME" ]]; then
    ENV_D="$REAL_HOME/.config/environment.d"
    ENV_CONF="$ENV_D/panfrost.conf"
    if [[ ! -f "$ENV_CONF" ]] || ! grep -q 'PAN_MESA_DEBUG=noafbc' "$ENV_CONF"; then
        install -d -o "$REAL_USER" -g "$REAL_USER" "$ENV_D"
        echo 'PAN_MESA_DEBUG=noafbc' > "$ENV_CONF"
        chown "$REAL_USER:$REAL_USER" "$ENV_CONF"
        echo "  wrote $ENV_CONF"
        changed=1
    else
        echo "  already present ($ENV_CONF)"
    fi
    BASHRC="$REAL_HOME/.bashrc"
    if [[ -f "$BASHRC" ]] && grep -q 'PAN_MESA_DEBUG=noafbc' "$BASHRC"; then
        echo "  already present ($BASHRC)"
    elif [[ -f "$BASHRC" ]]; then
        echo 'export PAN_MESA_DEBUG=noafbc' >> "$BASHRC"
        echo "  appended to $BASHRC"
        changed=1
    fi
fi

echo "== 4. Persistent journal =="
JOURNALD_D=/etc/systemd/journald.conf.d/persistent.conf
if [[ -f "$JOURNALD_D" ]]; then
    echo "  already present ($JOURNALD_D)"
else
    mkdir -p /etc/systemd/journald.conf.d
    cat > "$JOURNALD_D" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=256M
SyncIntervalSec=1m
EOF
    echo "  wrote $JOURNALD_D"
    systemctl restart systemd-journald
    changed=1
fi

echo "== 5. Panic-on-oops + reboot on panic =="
SYSCTL_D=/etc/sysctl.d/99-panic-reboot.conf
if [[ -f "$SYSCTL_D" ]]; then
    echo "  already present ($SYSCTL_D)"
else
    cat > "$SYSCTL_D" <<'EOF'
kernel.panic = 30
kernel.panic_on_oops = 1
EOF
    sysctl --system > /dev/null
    echo "  wrote $SYSCTL_D and applied"
    changed=1
fi

echo
echo "== Sanity check: GPU DVFS (gpu-mali.dtbo mali_sram-supply fix) =="
if dmesg | grep -q "Couldn't update frequency transition information"; then
    echo "  BROKEN: devfreq registration error present -- see docs/gpu-acceleration.md Fix 1"
    echo "  (dtbo patch on the firmware partition may be needed; this script does not apply it automatically)"
else
    CUR=/sys/bus/platform/devices/13000000.gpu/devfreq/13000000.gpu/available_frequencies
    if [[ -f "$CUR" ]] && [[ $(wc -w < "$CUR") -ge 16 ]]; then
        echo "  OK: $(wc -w < "$CUR") OPP levels available, no devfreq error in dmesg"
    else
        echo "  UNKNOWN: check manually -- $CUR missing or fewer than 16 OPPs"
    fi
fi

echo
if [[ $changed -eq 1 ]]; then
    echo "Changes were made. A reboot is required for the modprobe blacklist and boot args to take effect:"
    echo "  sudo reboot"
else
    echo "Nothing to do -- all fixes already in place."
fi

echo
echo "Don't forget: sudo bash scripts/hold-kernel.sh (kernel/DTB/u-boot apt holds)"
