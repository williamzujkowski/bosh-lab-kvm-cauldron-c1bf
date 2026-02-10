#!/usr/bin/env bash
# create-director.sh — Runs INSIDE the mgmt VM
# Creates (or converges) BOSH Director with CredHub enabled using bosh-deployment.
# Idempotent: re-running will converge the director, not recreate it.

set -euo pipefail

BOSH_DEPLOYMENT_COMMIT="faf834a"
LIBVIRT_CPI_VERSION="4.1"
STATE_DIR="/mnt/state"
LOCAL_STATE="/home/bosh/state"
DEPLOY_DIR="/home/bosh/bosh-deployment"

mkdir -p "$LOCAL_STATE" "$STATE_DIR/creds"

# --- Clone or update bosh-deployment ---
if [ -d "$DEPLOY_DIR" ]; then
  echo "[create-director] bosh-deployment already cloned, checking commit..."
  cd "$DEPLOY_DIR"
  CURRENT_COMMIT=$(git rev-parse --short HEAD)
  if [ "$CURRENT_COMMIT" = "$BOSH_DEPLOYMENT_COMMIT" ]; then
    echo "[create-director] Already at pinned commit ${BOSH_DEPLOYMENT_COMMIT}."
  else
    echo "[create-director] Checking out pinned commit ${BOSH_DEPLOYMENT_COMMIT}..."
    git fetch origin
    git checkout "$BOSH_DEPLOYMENT_COMMIT"
  fi
else
  echo "[create-director] Cloning bosh-deployment..."
  git clone https://github.com/cloudfoundry/bosh-deployment.git "$DEPLOY_DIR"
  cd "$DEPLOY_DIR"
  git checkout "$BOSH_DEPLOYMENT_COMMIT"
fi

# --- Determine state file locations ---
# If vars-store exists in host state, use it (cattle pattern)
VARS_STORE="${STATE_DIR}/vars-store.yml"
DIRECTOR_STATE="${STATE_DIR}/creds/director-state.json"

# Touch files if they don't exist (first run)
touch "$VARS_STORE"
[ -f "$DIRECTOR_STATE" ] || echo '{}' > "$DIRECTOR_STATE"

# --- Check if director already exists ---
if bosh env --environment 10.245.0.2 2>/dev/null; then
  echo "[create-director] Director already running. Converging..."
fi

# --- Create/converge BOSH Director ---
echo "[create-director] Running bosh create-env..."
bosh create-env "${DEPLOY_DIR}/bosh.yml" \
  --state="$DIRECTOR_STATE" \
  --vars-store="$VARS_STORE" \
  -o "${DEPLOY_DIR}/virtualbox/cpi.yml" \
  -o "${DEPLOY_DIR}/virtualbox/outbound-network.yml" \
  -o "${DEPLOY_DIR}/bosh-lite.yml" \
  -o "${DEPLOY_DIR}/bosh-lite-runc.yml" \
  -o "${DEPLOY_DIR}/credhub.yml" \
  -o "${DEPLOY_DIR}/uaa.yml" \
  -o "${DEPLOY_DIR}/jumpbox-user.yml" \
  -o /home/bosh/manifests/director/ops/libvirt-cpi.yml \
  -v director_name=bosh-lab \
  -v internal_ip=10.245.0.2 \
  -v internal_gw=10.245.0.1 \
  -v internal_cidr=10.245.0.0/24 \
  -v outbound_network_name=NatNetwork \
  2>&1

# --- Alias the environment ---
echo "[create-director] Setting up BOSH environment alias 'lab'..."
bosh alias-env lab \
  -e 10.245.0.2 \
  --ca-cert <(bosh int "$VARS_STORE" --path /director_ssl/ca)

# --- Log in ---
echo "[create-director] Logging in to BOSH Director..."
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET
BOSH_CLIENT_SECRET=$(bosh int "$VARS_STORE" --path /admin_password)

bosh -e lab env

# --- Copy vars-store to host state for persistence ---
cp "$VARS_STORE" "${STATE_DIR}/vars-store.yml"
cp "$DIRECTOR_STATE" "${STATE_DIR}/creds/director-state.json"

echo "[create-director] Director created and verified."
echo "[create-director] BOSH environment 'lab' is ready."
