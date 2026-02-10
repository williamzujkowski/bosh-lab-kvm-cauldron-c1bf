#!/usr/bin/env bash
# credhub-smoke.sh — Runs INSIDE the mgmt VM
# Verifies CredHub is accessible and functional.

set -euo pipefail

STATE_DIR="/mnt/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"

# --- Extract CredHub credentials from vars-store ---
CREDHUB_SERVER="https://192.168.50.6:8844"
CREDHUB_CA_CERT=$(bosh int "$VARS_STORE" --path /credhub_tls/ca)
UAA_CA_CERT=$(bosh int "$VARS_STORE" --path /uaa_ssl/ca 2>/dev/null || echo "")
CREDHUB_CLIENT="credhub-admin"
CREDHUB_SECRET=$(bosh int "$VARS_STORE" --path /credhub_admin_client_secret)

# CredHub CLI needs both CredHub and UAA CA certs for TLS verification
CA_CERT_FILE=$(mktemp)
echo "$CREDHUB_CA_CERT" > "$CA_CERT_FILE"
[ -n "$UAA_CA_CERT" ] && echo "$UAA_CA_CERT" >> "$CA_CERT_FILE"
trap 'rm -f "$CA_CERT_FILE"' EXIT

echo "[credhub-smoke] Logging in to CredHub at ${CREDHUB_SERVER}..."
credhub login \
  -s "$CREDHUB_SERVER" \
  --client-name="$CREDHUB_CLIENT" \
  --client-secret="$CREDHUB_SECRET" \
  --ca-cert "$CA_CERT_FILE"

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
