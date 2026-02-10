#!/usr/bin/env bash
# One-time libvirt configuration for BOSH lab.
# Configures QEMU to run without security restrictions so VMs can access
# disk files, cloud-init ISOs, and 9p filesystem shares.
# This is appropriate for a LOCAL DEVELOPER LAB — not for production.
#
# What it does:
#   1. Sets security_driver = "none" (disables AppArmor/DAC for QEMU)
#   2. Sets user/group = "root" (QEMU runs as root, can access all paths)
#   3. Restarts libvirtd
#
# Usage: sudo ./scripts/setup-libvirt.sh

set -euo pipefail

QEMU_CONF="/etc/libvirt/qemu.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)." >&2
    exit 1
fi

echo "==> Configuring libvirt for BOSH lab..."

NEEDS_RESTART=false

# Check if already fully configured
if grep -q '^security_driver = "none"' "$QEMU_CONF" 2>/dev/null && \
   grep -q '^user = "root"' "$QEMU_CONF" 2>/dev/null; then
    echo "    Already configured. Nothing to do."
    exit 0
fi

# Backup original
cp "$QEMU_CONF" "${QEMU_CONF}.bak.$(date +%s)"

# Configure security_driver
if ! grep -q '^security_driver = "none"' "$QEMU_CONF" 2>/dev/null; then
    if grep -q '#security_driver = ' "$QEMU_CONF" 2>/dev/null; then
        sed -i 's/#security_driver = .*/security_driver = "none"/' "$QEMU_CONF"
    else
        echo '' >> "$QEMU_CONF"
        echo '# BOSH lab: disable security drivers for local dev use' >> "$QEMU_CONF"
        echo 'security_driver = "none"' >> "$QEMU_CONF"
    fi
    echo "    Set security_driver = \"none\""
    NEEDS_RESTART=true
fi

# Configure QEMU user/group — run as root so it can access user home dirs
if ! grep -q '^user = "root"' "$QEMU_CONF" 2>/dev/null; then
    if grep -q '#user = ' "$QEMU_CONF" 2>/dev/null; then
        sed -i 's/#user = .*/user = "root"/' "$QEMU_CONF"
    else
        echo 'user = "root"' >> "$QEMU_CONF"
    fi
    echo "    Set user = \"root\""
    NEEDS_RESTART=true
fi

if ! grep -q '^group = "root"' "$QEMU_CONF" 2>/dev/null; then
    if grep -q '#group = ' "$QEMU_CONF" 2>/dev/null; then
        sed -i 's/#group = .*/group = "root"/' "$QEMU_CONF"
    else
        echo 'group = "root"' >> "$QEMU_CONF"
    fi
    echo "    Set group = \"root\""
    NEEDS_RESTART=true
fi

if [ "$NEEDS_RESTART" = true ]; then
    echo "    Restarting libvirtd..."
    systemctl restart libvirtd
fi

echo ""
echo "==> Libvirt configured for BOSH lab."
echo "    You can now run: make up && make bootstrap"
