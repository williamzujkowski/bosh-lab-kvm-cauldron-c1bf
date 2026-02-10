#!/usr/bin/env bash
# bootstrap.sh — Main orchestrator for BOSH lab provisioning
# Runs on the HOST, SSHs into the mgmt VM for remote steps.
#
# Usage: ./bootstrap/bootstrap.sh [--skip-tools] [--skip-director] [--concourse-only]
#
# Idempotent: safe to re-run. Will not recreate the director if it already exists
# unless you explicitly run 'make reset' first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- Parse flags ---
SKIP_TOOLS=false
SKIP_DIRECTOR=false
CONCOURSE_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --skip-tools)     SKIP_TOOLS=true ;;
    --skip-director)  SKIP_DIRECTOR=true ;;
    --concourse-only) CONCOURSE_ONLY=true; SKIP_TOOLS=true; SKIP_DIRECTOR=true ;;
    *) log_warn "Unknown flag: $arg" ;;
  esac
done

# --- Ensure state dirs exist ---
ensure_state_dirs

# --- Generate SSH key if needed ---
SSH_KEY="${CREDS_DIR}/mgmt_ssh"
if [ ! -f "$SSH_KEY" ]; then
  log_step "Generating SSH key for mgmt VM access"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "bosh-lab-mgmt"
  log_info "SSH key generated at ${SSH_KEY}"
else
  log_info "SSH key already exists at ${SSH_KEY}"
fi

MGMT_IP="10.245.0.2"
SSH_OPTS="-i ${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
SSH_CMD="ssh ${SSH_OPTS} bosh@${MGMT_IP}"
SCP_CMD="scp ${SSH_OPTS}"

# --- Wait for VM to be reachable ---
log_step "Waiting for mgmt VM at ${MGMT_IP} to become reachable..."
retry 30 5 "ssh ${SSH_OPTS} bosh@${MGMT_IP} true 2>/dev/null"
log_info "VM is reachable."

# --- Wait for cloud-init to complete ---
log_step "Waiting for cloud-init to finish..."
retry 60 5 "${SSH_CMD} 'test -f /var/log/bosh-lab-init.log' 2>/dev/null"
log_info "Cloud-init complete."

# --- Copy bootstrap scripts to VM ---
log_step "Copying bootstrap scripts to VM"
${SSH_CMD} "mkdir -p /home/bosh/bootstrap/remote /home/bosh/bootstrap/lib"
${SCP_CMD} "${SCRIPT_DIR}/lib/"*.sh "bosh@${MGMT_IP}:/home/bosh/bootstrap/lib/"
${SCP_CMD} "${SCRIPT_DIR}/remote/"*.sh "bosh@${MGMT_IP}:/home/bosh/bootstrap/remote/"
${SSH_CMD} "chmod +x /home/bosh/bootstrap/remote/*.sh /home/bosh/bootstrap/lib/*.sh"

# --- Copy manifests to VM ---
log_step "Copying manifests to VM"
${SSH_CMD} "mkdir -p /home/bosh/manifests/{director/ops,cloud-config,concourse}"
${SCP_CMD} -r "${REPO_ROOT}/manifests/director/"* "bosh@${MGMT_IP}:/home/bosh/manifests/director/" 2>/dev/null || true
${SCP_CMD} -r "${REPO_ROOT}/manifests/cloud-config/"* "bosh@${MGMT_IP}:/home/bosh/manifests/cloud-config/" 2>/dev/null || true
${SCP_CMD} -r "${REPO_ROOT}/manifests/concourse/"* "bosh@${MGMT_IP}:/home/bosh/manifests/concourse/" 2>/dev/null || true

# --- Copy stemcell patches to VM ---
log_step "Copying stemcell patches to VM"
${SSH_CMD} "mkdir -p /home/bosh/stemcell-patches"
${SCP_CMD} "${REPO_ROOT}/stemcell-patches/"* "bosh@${MGMT_IP}:/home/bosh/stemcell-patches/"
${SSH_CMD} "chmod +x /home/bosh/stemcell-patches/*.sh"

# --- Step 1: Install tools ---
if [ "$SKIP_TOOLS" = false ]; then
  log_step "Installing BOSH + CredHub CLIs on mgmt VM"
  ${SSH_CMD} "/home/bosh/bootstrap/remote/install-tools.sh" 2>&1 | tee "${LOG_DIR}/install-tools.log"
else
  log_info "Skipping tool installation (--skip-tools)"
fi

# --- Step 2: Create Director ---
if [ "$SKIP_DIRECTOR" = false ]; then
  log_step "Creating BOSH Director with CredHub"
  # Start create-env (runs detached because it disrupts VM networking)
  ${SSH_CMD} "/home/bosh/bootstrap/remote/create-director.sh" 2>&1 | tee "${LOG_DIR}/create-director.log"

  # Poll for completion — SSH may drop during create-env, so we retry
  log_step "Waiting for bosh create-env to complete (this takes 10-20 minutes)..."
  log_info "VM networking may be disrupted during container creation."
  log_info "You can monitor progress via: virt-manager (VM console)"

  POLL_ATTEMPTS=0
  MAX_POLL_ATTEMPTS=120  # 120 * 15s = 30 minutes max
  while [ $POLL_ATTEMPTS -lt $MAX_POLL_ATTEMPTS ]; do
    POLL_ATTEMPTS=$((POLL_ATTEMPTS + 1))
    sleep 15

    # Try to check completion status
    RC_FILE_CONTENT=$(${SSH_CMD} "cat /home/bosh/state/create-env.rc 2>/dev/null" 2>/dev/null || echo "PENDING")

    if [ "$RC_FILE_CONTENT" = "0" ]; then
      log_info "bosh create-env completed successfully!"
      # Show the log
      ${SSH_CMD} "tail -20 /home/bosh/state/create-env.log" 2>/dev/null || true
      break
    elif [ "$RC_FILE_CONTENT" != "PENDING" ] && [ "$RC_FILE_CONTENT" != "" ]; then
      log_warn "bosh create-env failed with exit code: ${RC_FILE_CONTENT}"
      ${SSH_CMD} "tail -30 /home/bosh/state/create-env.log" 2>/dev/null || true
      exit 1
    fi

    # Still running or SSH is down
    if [ $((POLL_ATTEMPTS % 4)) -eq 0 ]; then
      ELAPSED=$((POLL_ATTEMPTS * 15))
      log_info "Still waiting... (${ELAPSED}s elapsed)"
    fi
  done

  if [ $POLL_ATTEMPTS -ge $MAX_POLL_ATTEMPTS ]; then
    log_warn "Timed out waiting for bosh create-env (30 minutes)."
    exit 1
  fi

  # Finalize director setup (alias, login)
  log_step "Finalizing director configuration..."
  ${SSH_CMD} "/home/bosh/bootstrap/remote/finalize-director.sh" 2>&1 | tee "${LOG_DIR}/finalize-director.log"
else
  log_info "Skipping director creation (--skip-director)"
fi

# --- Step 3: Configure cloud-config ---
if [ "$SKIP_DIRECTOR" = false ]; then
  log_step "Applying cloud-config"
  ${SSH_CMD} "/home/bosh/bootstrap/remote/configure-cloud.sh" 2>&1 | tee "${LOG_DIR}/configure-cloud.log"
fi

# --- Step 4: CredHub smoke test ---
if [ "$SKIP_DIRECTOR" = false ]; then
  log_step "Running CredHub smoke test"
  ${SSH_CMD} "/home/bosh/bootstrap/remote/credhub-smoke.sh" 2>&1 | tee "${LOG_DIR}/credhub-smoke.log"
fi

# --- Step 5: Deploy Concourse ---
if [ "$CONCOURSE_ONLY" = true ] || [ "$SKIP_DIRECTOR" = false ]; then
  log_step "Deploying Concourse via BOSH"
  ${SSH_CMD} "/home/bosh/bootstrap/remote/concourse-deploy.sh" 2>&1 | tee "${LOG_DIR}/concourse-deploy.log"
fi

# --- Copy vars-store back to host state ---
log_step "Syncing credentials back to host state directory"
${SCP_CMD} "bosh@${MGMT_IP}:/home/bosh/state/creds.yml" "${CREDS_DIR}/creds.yml" 2>/dev/null || true
${SCP_CMD} "bosh@${MGMT_IP}:/home/bosh/state/vars-store.yml" "${STATE_DIR}/vars-store.yml" 2>/dev/null || true

echo ""
log_step "Bootstrap complete!"
log_info "BOSH Director: ${MGMT_IP}"
log_info "Run 'make env' to set up your shell, then 'bosh -e lab env' to verify."
log_info "Concourse UI: ${CONCOURSE_EXTERNAL_URL} (after 'make concourse')"
