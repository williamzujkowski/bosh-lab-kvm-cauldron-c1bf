#!/usr/bin/env bash
# finalize-director.sh — Runs INSIDE the mgmt VM
# Called after bosh create-env completes to alias the environment and verify.

set -euo pipefail

STATE_DIR="/mnt/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"

# --- Alias the environment ---
echo "[create-director] Setting up BOSH environment alias 'lab'..."
bosh alias-env lab \
  -e 192.168.50.6 \
  --ca-cert <(bosh int "$VARS_STORE" --path /director_ssl/ca)

# --- Log in ---
echo "[create-director] Logging in to BOSH Director..."
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET
BOSH_CLIENT_SECRET=$(bosh int "$VARS_STORE" --path /admin_password)

bosh -e lab env

echo "[create-director] Director created and verified."
echo "[create-director] BOSH environment 'lab' is ready."
