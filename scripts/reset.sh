#!/usr/bin/env bash
# reset.sh — DANGEROUS: Destroy all VMs, networks, and wipe state
# Called by 'make reset' after user confirmation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${REPO_ROOT}/state"
TF_ENV="${REPO_ROOT}/terraform/envs/laptop"

echo "[reset] Destroying Terraform resources..."
cd "$TF_ENV" && terraform destroy -auto-approve -input=false \
  -var="cloud_image_path=${STATE_DIR}/cache/jammy-server-cloudimg-amd64.img" \
  -var="cloud_init_path=${STATE_DIR}/mgmt-cloudinit.yaml" \
  -var="state_dir=${STATE_DIR}" \
  2>/dev/null || echo "[reset] Terraform destroy completed (may have had no state)."

echo "[reset] Cleaning up libvirt resources..."
virsh destroy bosh-lab-mgmt 2>/dev/null || true
virsh undefine bosh-lab-mgmt --remove-all-storage 2>/dev/null || true
virsh net-destroy bosh-lab 2>/dev/null || true
virsh net-undefine bosh-lab 2>/dev/null || true
virsh pool-destroy bosh-lab 2>/dev/null || true
virsh pool-undefine bosh-lab 2>/dev/null || true

echo "[reset] Wiping state directory..."
rm -rf "${STATE_DIR}"

echo "[reset] Removing Terraform lock files..."
rm -rf "${TF_ENV}/.terraform" "${TF_ENV}/.terraform.lock.hcl"

echo ""
echo "[reset] Complete. All lab resources destroyed."
echo "        Run 'make up && make bootstrap' for a fresh start."
