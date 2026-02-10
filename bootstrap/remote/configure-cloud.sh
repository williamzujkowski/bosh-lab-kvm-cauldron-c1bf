#!/usr/bin/env bash
# configure-cloud.sh — Runs INSIDE the mgmt VM
# Applies cloud-config and runtime-config to the BOSH Director.

set -euo pipefail

STATE_DIR="/mnt/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"

# --- Set up BOSH auth ---
export BOSH_ENVIRONMENT=lab
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET
BOSH_CLIENT_SECRET=$(bosh int "$VARS_STORE" --path /admin_password)
export BOSH_CA_CERT
BOSH_CA_CERT=$(bosh int "$VARS_STORE" --path /director_ssl/ca)

# --- Apply cloud-config ---
echo "[configure-cloud] Applying cloud-config..."
if [ -f /home/bosh/manifests/cloud-config/cloud-config.yml ]; then
  bosh -n update-cloud-config /home/bosh/manifests/cloud-config/cloud-config.yml
  echo "[configure-cloud] Cloud-config applied."
else
  echo "[configure-cloud] WARNING: cloud-config.yml not found, skipping."
fi

# --- Apply runtime-config ---
echo "[configure-cloud] Applying runtime-config..."
if [ -f /home/bosh/manifests/cloud-config/runtime-config.yml ]; then
  bosh -n update-runtime-config /home/bosh/manifests/cloud-config/runtime-config.yml
  echo "[configure-cloud] Runtime-config applied."
else
  echo "[configure-cloud] No runtime-config.yml found, skipping."
fi

echo "[configure-cloud] Cloud configuration complete."
