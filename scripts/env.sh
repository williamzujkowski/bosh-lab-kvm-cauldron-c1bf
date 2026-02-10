#!/usr/bin/env bash
# env.sh — Print shell exports for bosh and credhub CLIs
# Usage: eval "$(./scripts/env.sh)" or source <(./scripts/env.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${REPO_ROOT}/state"
VARS_STORE="${STATE_DIR}/vars-store.yml"
SSH_KEY="${STATE_DIR}/creds/mgmt_ssh"
MGMT_IP="10.245.0.2"

if [ ! -f "$VARS_STORE" ]; then
  echo "# ERROR: vars-store.yml not found. Run 'make bootstrap' first." >&2
  exit 1
fi

if ! command -v bosh &>/dev/null; then
  echo "# ERROR: bosh CLI not found on host. Install from:" >&2
  echo "#   https://github.com/cloudfoundry/bosh-cli/releases" >&2
  exit 1
fi

# BOSH environment
BOSH_CLIENT="admin"
BOSH_CLIENT_SECRET=$(bosh int "$VARS_STORE" --path /admin_password 2>/dev/null || echo "UNKNOWN")
BOSH_CA_CERT=$(bosh int "$VARS_STORE" --path /director_ssl/ca 2>/dev/null || echo "")

cat <<EOF
# BOSH Lab Environment — source this or eval it
# Usage: eval "\$(./scripts/env.sh)"

export BOSH_ENVIRONMENT="${MGMT_IP}"
export BOSH_CLIENT="${BOSH_CLIENT}"
export BOSH_CLIENT_SECRET="${BOSH_CLIENT_SECRET}"
export BOSH_CA_CERT='${BOSH_CA_CERT}'

# CredHub
export CREDHUB_SERVER="https://${MGMT_IP}:8844"
export CREDHUB_CLIENT="credhub-admin"
export CREDHUB_CA_CERT='${BOSH_CA_CERT}'

# SSH to mgmt VM
alias bosh-ssh="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null bosh@${MGMT_IP}"

# Concourse tunnel (run in separate terminal)
alias concourse-tunnel="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -L 8443:10.245.0.10:443 -N bosh@${MGMT_IP}"

echo "BOSH Lab environment configured." >&2
echo "  bosh -e ${MGMT_IP} env" >&2
echo "  bosh-ssh  (alias to SSH into mgmt VM)" >&2
echo "  concourse-tunnel  (alias to set up Concourse SSH tunnel)" >&2
EOF
