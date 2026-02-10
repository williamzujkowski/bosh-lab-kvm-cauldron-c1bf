#!/usr/bin/env bash
# credhub-smoke.sh — Runs INSIDE the mgmt VM
# Verifies CredHub is accessible and functional.

set -euo pipefail

STATE_DIR="/mnt/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"

# --- Extract CredHub credentials from vars-store ---
CREDHUB_SERVER="https://10.245.0.2:8844"
CREDHUB_CA_CERT=$(bosh int "$VARS_STORE" --path /credhub_tls/ca)
CREDHUB_CLIENT="credhub-admin"
CREDHUB_SECRET=$(bosh int "$VARS_STORE" --path /credhub_admin_client_secret)

echo "[credhub-smoke] Logging in to CredHub at ${CREDHUB_SERVER}..."
credhub login \
  -s "$CREDHUB_SERVER" \
  --client-name="$CREDHUB_CLIENT" \
  --client-secret="$CREDHUB_SECRET" \
  --ca-cert=<(echo "$CREDHUB_CA_CERT")

echo "[credhub-smoke] CredHub login successful."

# --- Smoke test: set and get a value ---
TEST_CRED="/bosh-lab/smoke-test/test-value"
echo "[credhub-smoke] Setting test credential: ${TEST_CRED}..."
credhub set -n "$TEST_CRED" -t value -v "smoke-test-$(date +%s)"

echo "[credhub-smoke] Getting test credential..."
credhub get -n "$TEST_CRED"

echo "[credhub-smoke] Listing credentials..."
credhub find | head -20

echo "[credhub-smoke] Cleaning up test credential..."
credhub delete -n "$TEST_CRED"

echo "[credhub-smoke] CredHub smoke test PASSED."
