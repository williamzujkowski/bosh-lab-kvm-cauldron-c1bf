#!/usr/bin/env bash
# concourse-deploy.sh — Runs INSIDE the mgmt VM
# Deploys Concourse via BOSH onto the local IaaS.

set -euo pipefail

STATE_DIR="/mnt/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"
CONCOURSE_RELEASE_VERSION="7.11.2"
BPM_RELEASE_VERSION="1.2.19"
POSTGRES_RELEASE_VERSION="49"
STEMCELL_LINE="ubuntu-jammy"

# --- Set up BOSH auth ---
export BOSH_ENVIRONMENT=lab
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET
BOSH_CLIENT_SECRET=$(bosh int "$VARS_STORE" --path /admin_password)
export BOSH_CA_CERT
BOSH_CA_CERT=$(bosh int "$VARS_STORE" --path /director_ssl/ca)

# --- Fix Garden for nested container support ---
# Garden's init-bin defaults to /sbin/init (systemd) which crashes in nested
# containers. Fix it to use Guardian's init binary, unmount cgroup2 overlay,
# and verify nested containers work before attempting deployment.
GARDEN_FIX="/home/bosh/stemcell-patches/fix-garden-nested.sh"
if [ -x "$GARDEN_FIX" ]; then
  echo "[concourse-deploy] Applying Garden nested container fixes..."
  sudo "$GARDEN_FIX"
fi

# --- Start stemcell volume patcher (patches BPM for cgroup2 compatibility) ---
# Patches apply to both the host Garden's grootfs volumes (for the BOSH director
# container itself) and the BOSH container's internal Garden grootfs volumes
# (for deployment VMs like Concourse).
PATCH_WATCHER="/home/bosh/stemcell-patches/watch-and-patch.sh"
if [ -x "$PATCH_WATCHER" ]; then
  echo "[concourse-deploy] Starting stemcell volume patcher..."
  "$PATCH_WATCHER" &
  PATCHER_PID=$!
else
  PATCHER_PID=""
fi

# --- Patch inner grootfs volumes (inside the BOSH container) ---
# The host watcher only patches the outer Garden's volumes. Deployment VMs
# use the BOSH container's internal Garden, whose volumes need separate patching.
CONTAINER_ID=$(sudo /usr/sbin/runc list 2>/dev/null | awk '/running/ {print $1}' | head -1)
if [ -n "$CONTAINER_ID" ]; then
  CONTAINER_PID=$(sudo /usr/sbin/runc state "$CONTAINER_ID" 2>/dev/null | grep '"pid"' | grep -o '[0-9]*')
  if [ -n "$CONTAINER_PID" ]; then
    # Copy patches into BOSH container
    sudo cp -r /home/bosh/stemcell-patches/* "/proc/${CONTAINER_PID}/root/tmp/stemcell-patches/" 2>/dev/null || true
    # Patch all existing inner volumes
    sudo nsenter -t "$CONTAINER_PID" -m -u -i -n -p -- /bin/bash -c '
      PATCH_DIR=/tmp/stemcell-patches
      [ -x "$PATCH_DIR/apply-patches.sh" ] || exit 0
      for store in /var/vcap/data/grootfs/store/unprivileged/volumes /var/vcap/data/grootfs/store/privileged/volumes; do
        [ -d "$store" ] || continue
        for vol in "$store"/*/; do
          [ -d "$vol" ] || continue
          "$PATCH_DIR/apply-patches.sh" "$vol" 2>/dev/null || true
        done
      done
    ' 2>/dev/null || true
  fi
fi

# --- Upload stemcell if needed ---
echo "[concourse-deploy] Checking stemcell..."
STEMCELL_UPLOADED=$(bosh -e lab stemcells --json | jq -r ".Tables[0].Rows // [] | map(select(.os == \"${STEMCELL_LINE}\")) | length")
if [ "${STEMCELL_UPLOADED:-0}" = "0" ]; then
  echo "[concourse-deploy] Uploading stemcell from bosh.io..."
  STEMCELL_URL="https://bosh.io/d/stemcells/bosh-warden-boshlite-${STEMCELL_LINE}-go_agent"
  bosh -e lab upload-stemcell "$STEMCELL_URL"
else
  echo "[concourse-deploy] Stemcell already uploaded."
fi

# --- Upload BPM release if needed ---
echo "[concourse-deploy] Checking BPM release..."
BPM_UPLOADED=$(bosh -e lab releases --json | jq -r ".Tables[0].Rows // [] | map(select(.name == \"bpm\")) | length")
if [ "${BPM_UPLOADED:-0}" = "0" ]; then
  echo "[concourse-deploy] Uploading BPM release from bosh.io..."
  BPM_URL="https://bosh.io/d/github.com/cloudfoundry/bpm-release?v=${BPM_RELEASE_VERSION}"
  bosh -e lab upload-release "$BPM_URL"
else
  echo "[concourse-deploy] BPM release already uploaded."
fi

# --- Upload Postgres release if needed ---
echo "[concourse-deploy] Checking Postgres release..."
PG_UPLOADED=$(bosh -e lab releases --json | jq -r ".Tables[0].Rows // [] | map(select(.name == \"postgres\")) | length")
if [ "${PG_UPLOADED:-0}" = "0" ]; then
  echo "[concourse-deploy] Uploading Postgres release from bosh.io..."
  PG_URL="https://bosh.io/d/github.com/cloudfoundry/postgres-release?v=${POSTGRES_RELEASE_VERSION}"
  bosh -e lab upload-release "$PG_URL"
else
  echo "[concourse-deploy] Postgres release already uploaded."
fi

# --- Upload Concourse release if needed ---
echo "[concourse-deploy] Checking Concourse release..."
RELEASE_UPLOADED=$(bosh -e lab releases --json | jq -r ".Tables[0].Rows // [] | map(select(.name == \"concourse\")) | length")
if [ "${RELEASE_UPLOADED:-0}" = "0" ]; then
  echo "[concourse-deploy] Uploading Concourse release from bosh.io..."
  RELEASE_URL="https://bosh.io/d/github.com/concourse/concourse-bosh-release?v=${CONCOURSE_RELEASE_VERSION}"
  bosh -e lab upload-release "$RELEASE_URL"
else
  echo "[concourse-deploy] Concourse release already uploaded."
fi

# --- Clean up stale deployment if agent is unresponsive ---
# On re-runs, the existing VM's agent may be unresponsive (e.g., after host
# hibernation or container restarts). Force-delete to avoid "Timed out
# sending 'get_state'" errors that block the new deployment.
EXISTING=$(bosh -e lab -d concourse instances --json 2>/dev/null | jq -r '.Tables[0].Rows // [] | length' 2>/dev/null || echo "0")
if [ "${EXISTING:-0}" != "0" ]; then
  echo "[concourse-deploy] Cleaning up existing deployment..."
  bosh -e lab delete-deployment -d concourse --force -n 2>/dev/null || true
  sleep 3
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
  -v external_url="http://10.245.0.10:8080" \
  -v web_ip="10.245.0.10" \
  -v network_name="default" \
  -v web_vm_type="default" \
  -v deployment_name="concourse"

# Stop patcher if still running
[ -n "${PATCHER_PID:-}" ] && kill "$PATCHER_PID" 2>/dev/null || true

echo "[concourse-deploy] Concourse deployed."
echo "[concourse-deploy] UI: http://10.245.0.10:8080"
echo "[concourse-deploy] To access from host, set up SSH tunnel:"
echo "  ssh -L 8080:10.245.0.10:8080 bosh@10.245.0.2"
echo ""
echo "[concourse-deploy] To login with fly:"
echo "  fly -t lab login -c http://127.0.0.1:8080 -u admin -p <password>"
echo "  Password is in: state/creds/concourse-vars.yml (path: /admin_password)"
