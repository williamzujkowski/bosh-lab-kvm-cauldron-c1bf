#!/usr/bin/env bash
# Common variables and functions shared across bootstrap scripts
# Usage: source bootstrap/lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="${REPO_ROOT}/state"
CREDS_DIR="${STATE_DIR}/creds"
CA_DIR="${STATE_DIR}/ca"
CACHE_DIR="${STATE_DIR}/cache"
LOG_DIR="${STATE_DIR}/logs"

# Version pins — single source of truth
BOSH_CLI_VERSION="7.9.17"
CREDHUB_CLI_VERSION="2.9.53"
BOSH_DEPLOYMENT_COMMIT="faf834a"  # Pin to known-good commit (2026-02-08)
LIBVIRT_CPI_VERSION="4.1"
CONCOURSE_RELEASE_VERSION="8.0.1"
STEMCELL_LINE="ubuntu-jammy"
STEMCELL_VERSION="1.1044"
FLY_VERSION="8.0.1"

# Network defaults
BOSH_NETWORK="10.245.0.0/24"
BOSH_GATEWAY="10.245.0.1"
BOSH_DIRECTOR_IP="10.245.0.2"
BOSH_INTERNAL_CIDR="10.245.0.0/24"

# Director
BOSH_ENVIRONMENT="lab"
BOSH_DIRECTOR_NAME="bosh-lab"

# Concourse
CONCOURSE_WEB_IP="10.245.0.10"
CONCOURSE_EXTERNAL_URL="https://127.0.0.1:8443"

# Source logging
# shellcheck source=bootstrap/lib/log.sh
source "${REPO_ROOT}/bootstrap/lib/log.sh"
# shellcheck source=bootstrap/lib/retry.sh
source "${REPO_ROOT}/bootstrap/lib/retry.sh"

ensure_state_dirs() {
  mkdir -p "$CREDS_DIR" "$CA_DIR" "$CACHE_DIR" "$LOG_DIR"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    log_fatal "Required command not found: $cmd. Run 'make doctor' to check prerequisites."
  fi
}
