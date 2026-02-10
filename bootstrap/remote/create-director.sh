#!/usr/bin/env bash
# create-director.sh — Runs INSIDE the mgmt VM
# Creates (or converges) BOSH Director with CredHub enabled using bosh-deployment.
# Idempotent: re-running will converge the director, not recreate it.
#
# NOTE: bosh create-env may disrupt VM networking (Garden/warden container setup).
# This script runs create-env via nohup so it survives SSH disconnection.
# The calling script (bootstrap.sh) polls for completion.

set -euo pipefail

BOSH_DEPLOYMENT_COMMIT="faf834a"
STATE_DIR="/mnt/state"
LOCAL_STATE="/home/bosh/state"
DEPLOY_DIR="/home/bosh/bosh-deployment"
CREATE_ENV_LOG="/home/bosh/state/create-env.log"
CREATE_ENV_PID="/home/bosh/state/create-env.pid"
CREATE_ENV_RC="/home/bosh/state/create-env.rc"

mkdir -p "$LOCAL_STATE" "$STATE_DIR/creds"

# --- Ensure Garden is running (required by warden CPI) ---
echo "[create-director] Setting up Garden..."
/home/bosh/bootstrap/remote/setup-garden.sh

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
VARS_STORE="${STATE_DIR}/vars-store.yml"
DIRECTOR_STATE="${STATE_DIR}/creds/director-state.json"

# Touch files if they don't exist (first run)
touch "$VARS_STORE"
[ -f "$DIRECTOR_STATE" ] || echo '{}' > "$DIRECTOR_STATE"

# --- Check if create-env is already running ---
if [ -f "$CREATE_ENV_PID" ]; then
  OLD_PID=$(cat "$CREATE_ENV_PID")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[create-director] bosh create-env already running (PID $OLD_PID). Waiting..."
    echo "RUNNING"
    exit 0
  fi
fi

# --- Check if director already exists ---
if bosh env --environment 192.168.50.6 2>/dev/null; then
  echo "[create-director] Director already running."
  echo "DONE"
  exit 0
fi

# --- Check if a previous run completed ---
if [ -f "$CREATE_ENV_RC" ]; then
  RC=$(cat "$CREATE_ENV_RC")
  if [ "$RC" = "0" ]; then
    echo "[create-director] Previous create-env succeeded."
    echo "DONE"
    exit 0
  else
    echo "[create-director] Previous create-env failed (rc=$RC). Retrying..."
    rm -f "$CREATE_ENV_RC" "$CREATE_ENV_PID"
  fi
fi

# --- Create/converge BOSH Director ---
# Run create-env via nohup so it survives SSH disconnection.
# Garden container networking may disrupt VM SSH connectivity.
echo "[create-director] Running bosh create-env (detached)..."
rm -f "$CREATE_ENV_RC"

# Stemcell patches fix Noble stemcell issues in Garden containers:
# - Missing runsvdir-start (Noble uses systemd, Garden needs runit)
# - BPM binary incompatible with cgroup2
# - Missing monit runit service definitions
# The watcher runs alongside create-env and patches the stemcell volume
# as soon as Garden creates it.
PATCH_WATCHER="/home/bosh/stemcell-patches/watch-and-patch.sh"

nohup bash -c '
  # Start stemcell volume patcher in background
  if [ -x "'"$PATCH_WATCHER"'" ]; then
    "'"$PATCH_WATCHER"'" &
  fi

  bosh create-env "'"${DEPLOY_DIR}"'/bosh.yml" \
    --state="'"$DIRECTOR_STATE"'" \
    --vars-store="'"$VARS_STORE"'" \
    -o "'"${DEPLOY_DIR}"'/bosh-lite.yml" \
    -o "'"${DEPLOY_DIR}"'/bosh-lite-runc.yml" \
    -o /home/bosh/manifests/director/ops/warden-cloud-provider.yml \
    -o "'"${DEPLOY_DIR}"'/uaa.yml" \
    -o "'"${DEPLOY_DIR}"'/credhub.yml" \
    -o "'"${DEPLOY_DIR}"'/jumpbox-user.yml" \
    -v director_name=bosh-lab \
    -v internal_ip=192.168.50.6 \
    -v internal_gw=192.168.50.1 \
    -v internal_cidr=192.168.50.0/24 \
    2>&1
  echo $? > "'"$CREATE_ENV_RC"'"
' > "$CREATE_ENV_LOG" 2>&1 &

echo $! > "$CREATE_ENV_PID"
echo "[create-director] bosh create-env started (PID $(cat "$CREATE_ENV_PID"))."
echo "[create-director] Log: $CREATE_ENV_LOG"
echo "STARTED"
