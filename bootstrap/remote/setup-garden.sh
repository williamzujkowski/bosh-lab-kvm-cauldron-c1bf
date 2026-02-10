#!/usr/bin/env bash
# setup-garden.sh — Runs INSIDE the mgmt VM
# Installs Garden (gdn) + grootfs from the compiled garden-runc release
# and starts it as a systemd service.
# Required by warden CPI for bosh create-env.
# Idempotent: skips if Garden is already running.

set -euo pipefail

GARDEN_VERSION="1.83.0"
GARDEN_DIR="/opt/garden"
GARDEN_DATA="/var/lib/garden"
GARDEN_PORT=7777
GROOTFS_IMG="${GARDEN_DATA}/grootfs.img"
GROOTFS_STORE="${GARDEN_DATA}/grootfs/store"
GROOTFS_SIZE_MB=20480  # 20 GB

# Check if Garden is already running
if sudo systemctl is-active --quiet garden 2>/dev/null; then
  echo "[garden] Garden is already running."
  exit 0
fi

echo "[garden] Installing Garden ${GARDEN_VERSION}..."

# Download compiled release if not cached
RELEASE_URL="https://s3.amazonaws.com/bosh-compiled-release-tarballs/garden-runc-${GARDEN_VERSION}-ubuntu-noble-1.215.tgz"
CACHE_DIR="/tmp/garden-install"
mkdir -p "$CACHE_DIR"

if [ ! -f "$CACHE_DIR/garden-runc.tgz" ]; then
  echo "[garden] Downloading garden-runc release..."
  curl -sSL -o "$CACHE_DIR/garden-runc.tgz" "$RELEASE_URL"
fi

# Extract binaries
echo "[garden] Extracting binaries..."
cd "$CACHE_DIR"
mkdir -p extract guardian-pkg runc-pkg tini-pkg grootfs-pkg

tar xzf garden-runc.tgz -C extract \
  ./compiled_packages/guardian.tgz \
  ./compiled_packages/runc.tgz \
  ./compiled_packages/tini.tgz \
  ./compiled_packages/grootfs.tgz

tar xzf extract/compiled_packages/guardian.tgz -C guardian-pkg
tar xzf extract/compiled_packages/runc.tgz -C runc-pkg
tar xzf extract/compiled_packages/tini.tgz -C tini-pkg
tar xzf extract/compiled_packages/grootfs.tgz -C grootfs-pkg

# Install binaries
echo "[garden] Installing binaries to ${GARDEN_DIR}..."
sudo mkdir -p "${GARDEN_DIR}/bin" "${GARDEN_DATA}/depot"
sudo cp guardian-pkg/bin/gdn "${GARDEN_DIR}/bin/"
sudo cp guardian-pkg/bin/dadoo "${GARDEN_DIR}/bin/"
sudo cp guardian-pkg/bin/init "${GARDEN_DIR}/bin/"
sudo cp guardian-pkg/bin/nstar "${GARDEN_DIR}/bin/"
sudo cp runc-pkg/bin/runc "${GARDEN_DIR}/bin/"
sudo cp tini-pkg/bin/tini "${GARDEN_DIR}/bin/"
sudo cp grootfs-pkg/bin/grootfs "${GARDEN_DIR}/bin/"
sudo cp grootfs-pkg/bin/tardis "${GARDEN_DIR}/bin/"
sudo chmod +x "${GARDEN_DIR}/bin/"*

# Disable AppArmor restriction on unprivileged user namespaces (Noble 24.04+)
# Garden needs this for container creation with runc
echo "[garden] Configuring kernel for container support..."
if sysctl kernel.apparmor_restrict_unprivileged_userns 2>/dev/null | grep -q "= 1"; then
  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
  echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee /etc/sysctl.d/99-garden.conf > /dev/null
fi

# Create XFS loopback for grootfs (required — grootfs needs XFS)
if ! mountpoint -q "$GROOTFS_STORE" 2>/dev/null; then
  echo "[garden] Creating XFS loopback for grootfs store..."
  sudo mkdir -p "$GROOTFS_STORE"
  if [ ! -f "$GROOTFS_IMG" ]; then
    sudo dd if=/dev/zero of="$GROOTFS_IMG" bs=1M count=0 seek=${GROOTFS_SIZE_MB} 2>&1
    sudo mkfs.xfs "$GROOTFS_IMG"
  fi
  sudo mount -o loop "$GROOTFS_IMG" "$GROOTFS_STORE"

  # Add fstab entry for persistence across reboots
  if ! grep -q "grootfs.img" /etc/fstab; then
    echo "${GROOTFS_IMG} ${GROOTFS_STORE} xfs loop 0 0" | sudo tee -a /etc/fstab > /dev/null
  fi
fi

# Initialize grootfs store (required before first use)
echo "[garden] Initializing grootfs store..."
sudo "${GARDEN_DIR}/bin/grootfs" --store "$GROOTFS_STORE" \
  --tardis-bin "${GARDEN_DIR}/bin/tardis" \
  init-store

# Create systemd service
echo "[garden] Creating systemd service..."
sudo tee /etc/systemd/system/garden.service > /dev/null <<EOF
[Unit]
Description=Garden Container Manager
After=network.target

[Service]
Type=simple
ExecStart=${GARDEN_DIR}/bin/gdn server \\
  --bind-ip=127.0.0.1 \\
  --bind-port=${GARDEN_PORT} \\
  --depot=${GARDEN_DATA}/depot \\
  --log-level=error \\
  --runtime-plugin=${GARDEN_DIR}/bin/runc \\
  --dadoo-bin=${GARDEN_DIR}/bin/dadoo \\
  --init-bin=${GARDEN_DIR}/bin/init \\
  --nstar-bin=${GARDEN_DIR}/bin/nstar \\
  --tar-bin=/usr/bin/tar \\
  --allow-host-access \\
  --iptables-bin=/sbin/iptables \\
  --iptables-restore-bin=/sbin/iptables-restore \\
  --destroy-containers-on-startup \\
  --image-plugin=${GARDEN_DIR}/bin/grootfs \\
  --image-plugin-extra-arg=--store \\
  --image-plugin-extra-arg=${GROOTFS_STORE} \\
  --image-plugin-extra-arg=--tardis-bin \\
  --image-plugin-extra-arg=${GARDEN_DIR}/bin/tardis \\
  --privileged-image-plugin=${GARDEN_DIR}/bin/grootfs \\
  --privileged-image-plugin-extra-arg=--store \\
  --privileged-image-plugin-extra-arg=${GROOTFS_STORE} \\
  --privileged-image-plugin-extra-arg=--tardis-bin \\
  --privileged-image-plugin-extra-arg=${GARDEN_DIR}/bin/tardis
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable garden
sudo systemctl start garden

# Wait for Garden to be ready
echo "[garden] Waiting for Garden to start..."
for i in $(seq 1 30); do
  if curl -s "http://127.0.0.1:${GARDEN_PORT}/ping" >/dev/null 2>&1; then
    echo "[garden] Garden is running on port ${GARDEN_PORT}."
    exit 0
  fi
  sleep 1
done

echo "[garden] ERROR: Garden failed to start within 30 seconds."
sudo journalctl -u garden --no-pager -n 20
exit 1
