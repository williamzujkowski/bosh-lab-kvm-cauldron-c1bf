#!/usr/bin/env bash
# apply-patches.sh — Apply stemcell patches to the grootfs base volume
# Runs INSIDE the mgmt VM after Garden creates the first container.
#
# These patches fix Noble stemcell (1.215) issues in Garden containers:
# 1. runsvdir-start: Init script that sets up runit, monit, and patches BPM
# 2. bpm-shim: Replaces BPM binary that fails due to cgroup2 incompatibility
# 3. fake-systemctl: Translates systemd commands to runit equivalents
# 4. monit-run/monit-log-run: Runit service definitions for monit
#
# Usage: sudo ./apply-patches.sh [VOLUME_PATH]
# If VOLUME_PATH is not given, auto-detects the stemcell base volume.

set -euo pipefail

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-detect the stemcell base volume
if [ -n "${1:-}" ]; then
  VOL="$1"
else
  VOL=$(find /var/lib/garden/grootfs/store/volumes -maxdepth 1 -mindepth 1 -type d | head -1)
  if [ -z "$VOL" ]; then
    echo "Error: No grootfs volume found. Is Garden running?" >&2
    exit 1
  fi
fi

echo "[apply-patches] Patching stemcell volume: $VOL"

# 1. Install runsvdir-start (container init script)
cp "$PATCH_DIR/runsvdir-start" "$VOL/usr/sbin/runsvdir-start"
chmod +x "$VOL/usr/sbin/runsvdir-start"
echo "  Installed /usr/sbin/runsvdir-start"

# 2. Install BPM shim
cp "$PATCH_DIR/bpm-shim" "$VOL/usr/sbin/bpm-shim"
chmod +x "$VOL/usr/sbin/bpm-shim"
echo "  Installed /usr/sbin/bpm-shim"

# 3. Install fake systemctl
cp "$PATCH_DIR/fake-systemctl" "$VOL/usr/bin/systemctl"
chmod +x "$VOL/usr/bin/systemctl"
echo "  Installed /usr/bin/systemctl (fake)"

# 4. Install monit runit service
mkdir -p "$VOL/etc/sv/monit/log"
cp "$PATCH_DIR/monit-run" "$VOL/etc/sv/monit/run"
chmod +x "$VOL/etc/sv/monit/run"
cp "$PATCH_DIR/monit-log-run" "$VOL/etc/sv/monit/log/run"
chmod +x "$VOL/etc/sv/monit/log/run"
echo "  Installed monit runit service"

# 5. Create service symlink for runit
RUNIT_DEFAULT="$VOL/etc/runit/runsvdir/default"
if [ -d "$RUNIT_DEFAULT" ] && [ ! -e "$RUNIT_DEFAULT/monit" ]; then
  ln -sf /etc/sv/monit "$RUNIT_DEFAULT/monit"
  echo "  Created monit service symlink"
fi

# 6. Ensure /var/vcap/monit directory exists for svlogd
mkdir -p "$VOL/var/vcap/monit"

# 7. Fix resolv.conf — Noble stems have a symlink to systemd-resolved's stub,
#    which doesn't work inside BPM containers (no systemd-resolved running).
#    Replace with direct DNS servers so BPM process containers can resolve names.
if [ -L "$VOL/etc/resolv.conf" ] || ! [ -f "$VOL/etc/resolv.conf" ]; then
  rm -f "$VOL/etc/resolv.conf"
  cat > "$VOL/etc/resolv.conf" << 'DNSEOF'
nameserver 10.245.0.1
nameserver 8.8.8.8
options edns0
DNSEOF
  echo "  Fixed /etc/resolv.conf (replaced systemd-resolved stub)"
fi

echo "[apply-patches] All patches applied successfully."
