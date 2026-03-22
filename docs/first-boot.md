# First Boot — Radxa NIO 12L

This document covers everything from first power-on through a stable SSH session, including how to avoid the most painful gotchas.

---

## Power Setup

**This is the single most important thing to get right.**

The NIO 12L draws significantly more than a standard USB device:

| Power source | Max current | Result |
|-------------|-------------|--------|
| Laptop USB-C port | ~0.9 A (~4.5 W) | Board appears to boot but reboots constantly under any load |
| USB-A 3.0 port | ~0.9 A | Same — insufficient |
| 27 W USB-C PD adapter | 3 A @ 5 V = 15 W sustained | Stable |

**Use a dedicated USB-C PD charger (18 W or higher) in the right-side USB-C port.**

When running from insufficient power the board will:
- Power on and begin booting normally
- Reboot at some point during kernel init or userspace startup
- Repeat indefinitely — this looks like a firmware or software problem but it is purely a power issue

---

## Boot Loop Caused by GDM (no display connected)

Even with correct power, the board may enter a crash loop if **no monitor is connected** when GDM (the GNOME Display Manager) starts.

**Root cause:** `gnome-session-binary` fails with `Unrecoverable failure in required component org.gnome.Shell.desktop` when there is no display output. GDM immediately respawns it, creating an infinite crash-respawn loop that consumes all CPU and eventually destabilizes the system.

### Fix A — Temporarily disable GDM (headless operation)

If you want to run the board headless (SSH only), disable GDM entirely:

```bash
sudo systemctl disable gdm3
sudo systemctl set-default multi-user.target
sudo reboot
```

The board boots to CLI with no desktop. SSH works normally.

### Fix B — Connect a monitor first

When a monitor is connected at boot time, GDM and gnome-shell start successfully. See [`display-troubleshooting.md`](display-troubleshooting.md) for the full display bring-up checklist.

---

## Default Credentials & Forced Password Change

The Ubuntu image ships with credentials `ubuntu` / `ubuntu` but the password is **expired on first login**. SSH will connect but immediately drop you into a forced password-change dialog in the TTY — SSH command execution is blocked until the password is changed.

To change the password non-interactively from the host (using `expect`):

```bash
expect << 'EOF'
set timeout 30
set newpw "YourNewPassword"
spawn ssh -o StrictHostKeyChecking=no ubuntu@<board-ip>
expect "password:"
send "ubuntu\r"
expect "(current) UNIX password:"
send "ubuntu\r"
expect "New password:"
send "$newpw\r"
expect "Retype new password:"
send "$newpw\r"
expect "$ "
send "exit\r"
expect eof
EOF
```

> Ubuntu's PAM password policy requires mixed case, digits, and/or punctuation. A simple word will be rejected.

---

## Finding the Board's IP Address

The board gets its IP via DHCP on the ethernet port. Options for finding it:

```bash
# From your router's admin page (look for "mtk-genio" hostname)

# Or scan the local subnet from the host:
nmap -sn 192.168.0.0/24 | grep -A1 mtk-genio

# Or check ARP table after the board boots:
arp -n | grep -v incomplete
```

The board's hostname is `mtk-genio` by default.

---

## Verifying Boot Health

Once SSH is accessible:

```bash
# RAM — should show ~15.5 Gi total (16 GB physical, kernel overhead subtracted)
free -h

# Storage — should show ~234 GB total on /
df -h /

# Temperature — idle should be 60–70 °C with heatsinks attached
cat /sys/class/thermal/thermal_zone0/temp   # divide by 1000 for °C

# Uptime and load
uptime
```

---

## Setting Up SSH Key Auth

To avoid typing the password on every connection:

```bash
ssh-copy-id ubuntu@<board-ip>
```

Optionally disable password authentication afterward (edit `/etc/ssh/sshd_config` on the board: `PasswordAuthentication no`).

---

## System Updates

The image ships with several pending security updates. Apply them:

```bash
sudo apt update && sudo apt upgrade -y
```

> The image is locked to a point-in-time snapshot. Full dist-upgrade is not recommended without testing; kernel upgrades in particular may change MTK-specific patches.

---

## Useful System Info Commands

```bash
# Kernel version (should be MTK-patched)
uname -r
# → 5.15.0-1029-mtk

# CPU info
lscpu | grep -E 'Architecture|CPU|Model'

# GPU
ls /dev/dri/
cat /sys/kernel/debug/dri/0/name 2>/dev/null || dmesg | grep -i mali

# Thermal zones
paste <(cat /sys/class/thermal/thermal_zone*/type) \
      <(cat /sys/class/thermal/thermal_zone*/temp) | \
      awk '{printf "%s: %.1f°C\n", $1, $2/1000}'
```
