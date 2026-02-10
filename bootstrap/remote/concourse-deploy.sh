#!/usr/bin/env bash
# concourse-deploy.sh — Runs INSIDE the mgmt VM
# Deploys Concourse via BOSH onto the local IaaS.

set -euo pipefail

STATE_DIR="/mnt/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"
CONCOURSE_RELEASE_VERSION="7.14.1"
STEMCELL_LINE="ubuntu-jammy"
STEMCELL_VERSION="1.717"

# --- Set up BOSH auth ---
export BOSH_ENVIRONMENT=lab
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET
BOSH_CLIENT_SECRET=$(bosh int "$VARS_STORE" --path /admin_password)
export BOSH_CA_CERT
BOSH_CA_CERT=$(bosh int "$VARS_STORE" --path /director_ssl/ca)

# --- Upload stemcell if needed ---
echo "[concourse-deploy] Checking stemcell..."
STEMCELL_UPLOADED=$(bosh -e lab stemcells --json | jq -r ".Tables[0].Rows // [] | map(select(.os == \"${STEMCELL_LINE}\")) | length")
if [ "${STEMCELL_UPLOADED:-0}" = "0" ]; then
  STEMCELL_CACHE="${STATE_DIR}/cache/bosh-stemcell-${STEMCELL_VERSION}-warden-boshlite-${STEMCELL_LINE}-go_agent.tgz"
  if [ -f "$STEMCELL_CACHE" ]; then
    echo "[concourse-deploy] Uploading stemcell from cache..."
    bosh -e lab upload-stemcell "$STEMCELL_CACHE"
  else
    echo "[concourse-deploy] Uploading stemcell from bosh.io..."
    STEMCELL_URL="https://bosh.io/d/stemcells/bosh-warden-boshlite-${STEMCELL_LINE}-go_agent?v=${STEMCELL_VERSION}"
    bosh -e lab upload-stemcell "$STEMCELL_URL"
    # Cache for future use
    mkdir -p "${STATE_DIR}/cache"
    curl -sSL "$STEMCELL_URL" -o "$STEMCELL_CACHE" 2>/dev/null || true
  fi
else
  echo "[concourse-deploy] Stemcell already uploaded."
fi

# --- Upload Concourse release if needed ---
echo "[concourse-deploy] Checking Concourse release..."
RELEASE_UPLOADED=$(bosh -e lab releases --json | jq -r ".Tables[0].Rows // [] | map(select(.name == \"concourse\")) | length")
if [ "${RELEASE_UPLOADED:-0}" = "0" ]; then
  RELEASE_CACHE="${STATE_DIR}/cache/concourse-bosh-release-${CONCOURSE_RELEASE_VERSION}.tgz"
  if [ -f "$RELEASE_CACHE" ]; then
    echo "[concourse-deploy] Uploading Concourse release from cache..."
    bosh -e lab upload-release "$RELEASE_CACHE"
  else
    echo "[concourse-deploy] Uploading Concourse release from bosh.io..."
    RELEASE_URL="https://bosh.io/d/github.com/concourse/concourse-bosh-release?v=${CONCOURSE_RELEASE_VERSION}"
    bosh -e lab upload-release "$RELEASE_URL"
    mkdir -p "${STATE_DIR}/cache"
    curl -sSL "$RELEASE_URL" -o "$RELEASE_CACHE" 2>/dev/null || true
  fi
else
  echo "[concourse-deploy] Concourse release already uploaded."
fi

# --- Deploy Concourse ---
echo "[concourse-deploy] Deploying Concourse..."
CONCOURSE_MANIFEST="/home/bosh/manifests/concourse/concourse.yml"

if [ ! -f "$CONCOURSE_MANIFEST" ]; then
  echo "[concourse-deploy] ERROR: Concourse manifest not found at ${CONCOURSE_MANIFEST}"
  exit 1
fi

bosh -e lab -d concourse deploy "$CONCOURSE_MANIFEST" \
  -n \
  --vars-store="${STATE_DIR}/creds/concourse-vars.yml" \
  -v external_url="https://127.0.0.1:8443" \
  -v web_ip="10.245.0.10" \
  -v network_name="default" \
  -v web_vm_type="default" \
  -v db_vm_type="default" \
  -v worker_vm_type="default" \
  -v db_persistent_disk_type="default" \
  -v deployment_name="concourse"

echo "[concourse-deploy] Concourse deployed."
echo "[concourse-deploy] UI will be available at https://127.0.0.1:8443"
echo "[concourse-deploy] To access from host, set up SSH tunnel:"
echo "  ssh -L 8443:10.245.0.10:443 bosh@10.245.0.2"
echo ""
echo "[concourse-deploy] To login with fly:"
echo "  fly -t lab login -c https://127.0.0.1:8443 -u admin -p <password>"
echo "  Password is in: state/creds/concourse-vars.yml (path: /admin_password)"
