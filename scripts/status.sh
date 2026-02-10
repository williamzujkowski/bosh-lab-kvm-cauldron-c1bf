#!/usr/bin/env bash
# status.sh — Show the current state of the BOSH lab

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${REPO_ROOT}/state"
SSH_KEY="${STATE_DIR}/creds/mgmt_ssh"
MGMT_IP="10.245.0.2"
SSH_OPTS="-i ${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

echo "=== BOSH Lab Status ==="
echo ""

# --- VM Status ---
echo "--- Management VM ---"
if virsh dominfo bosh-lab-mgmt &>/dev/null; then
  STATE=$(virsh dominfo bosh-lab-mgmt | grep "State:" | awk '{print $2, $3}')
  echo "  VM: bosh-lab-mgmt (${STATE})"
else
  echo "  VM: NOT FOUND (run 'make up')"
fi

# --- Network ---
echo ""
echo "--- Network ---"
if virsh net-info bosh-lab &>/dev/null; then
  ACTIVE=$(virsh net-info bosh-lab | grep "Active:" | awk '{print $2}')
  echo "  Network: bosh-lab (Active: ${ACTIVE})"
else
  echo "  Network: NOT FOUND"
fi

# --- SSH Reachable ---
echo ""
echo "--- Connectivity ---"
if [ -f "$SSH_KEY" ] && ssh ${SSH_OPTS} bosh@${MGMT_IP} true 2>/dev/null; then
  echo "  SSH: OK (${MGMT_IP})"

  # --- BOSH Director ---
  echo ""
  echo "--- BOSH Director ---"
  if ssh ${SSH_OPTS} bosh@${MGMT_IP} "bosh -e lab env" 2>/dev/null; then
    echo "  Director: RUNNING"
  else
    echo "  Director: NOT RESPONDING (run 'make bootstrap')"
  fi

  # --- Concourse ---
  echo ""
  echo "--- Concourse ---"
  BOSH_AUTH='export BOSH_ENVIRONMENT=lab BOSH_CLIENT=admin; export BOSH_CLIENT_SECRET=$(bosh int /mnt/state/vars-store.yml --path /admin_password 2>/dev/null); export BOSH_CA_CERT="$(bosh int /mnt/state/vars-store.yml --path /director_ssl/ca 2>/dev/null)"'
  if ssh ${SSH_OPTS} bosh@${MGMT_IP} "${BOSH_AUTH}; bosh -d concourse instances" 2>/dev/null; then
    echo "  Concourse: DEPLOYED"
  else
    echo "  Concourse: NOT DEPLOYED (run 'make concourse')"
  fi
else
  echo "  SSH: UNREACHABLE (VM may be down)"
fi

# --- State Directory ---
echo ""
echo "--- State ---"
if [ -d "$STATE_DIR" ]; then
  echo "  State dir: EXISTS"
  [ -f "${STATE_DIR}/vars-store.yml" ] && echo "  vars-store.yml: PRESENT" || echo "  vars-store.yml: MISSING"
  [ -f "${SSH_KEY}" ] && echo "  SSH key: PRESENT" || echo "  SSH key: MISSING"
  [ -f "${STATE_DIR}/terraform.tfstate" ] && echo "  Terraform state: PRESENT" || echo "  Terraform state: MISSING"
else
  echo "  State dir: NOT FOUND (run 'make up')"
fi
