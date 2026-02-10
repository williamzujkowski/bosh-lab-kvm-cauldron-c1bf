# bosh-lab-kvm-cauldron-c1bf — BOSH + CredHub + Concourse Local Lab
# ================================================================
# One-command provisioning for developer laptops with KVM/libvirt.
#
# Usage:
#   make up          — Provision infrastructure (Terraform)
#   make bootstrap   — Bootstrap BOSH Director + CredHub
#   make concourse   — Deploy Concourse via BOSH
#   make env         — Print shell exports for bosh/credhub CLIs
#   make test        — Run acceptance tests
#   make status      — Show lab status
#   make logs        — Tail bootstrap logs
#   make down        — Destroy infrastructure (keeps state)
#   make reset       — DANGEROUS: Wipe state + destroy everything
#   make doctor      — Check host prerequisites

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Paths
REPO_ROOT   := $(shell pwd)
STATE_DIR   := $(REPO_ROOT)/state
TF_DIR      := $(REPO_ROOT)/terraform
TF_ENV      := $(TF_DIR)/envs/laptop
CLOUD_INIT  := $(REPO_ROOT)/cloud-init/mgmt.yaml
CACHE_DIR   := $(STATE_DIR)/cache
CLOUD_IMAGE := $(CACHE_DIR)/jammy-server-cloudimg-amd64.img
CLOUD_IMAGE_URL := https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# VM access
MGMT_IP     := 10.245.0.2
SSH_KEY     := $(STATE_DIR)/creds/mgmt_ssh
SSH_OPTS    := -i $(SSH_KEY) -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR

.PHONY: help up bootstrap concourse env test status logs down reset doctor image setup

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- Prerequisites ---

$(STATE_DIR):
	mkdir -p $(STATE_DIR)/{creds,ca,cache,logs}

setup: ## One-time libvirt config (requires sudo)
	@sudo $(REPO_ROOT)/scripts/setup-libvirt.sh

image: $(STATE_DIR) ## Download Ubuntu cloud image (cached)
	@if [ -f "$(CLOUD_IMAGE)" ]; then \
		echo "[image] Cloud image already cached."; \
	else \
		echo "[image] Downloading Ubuntu 22.04 cloud image..."; \
		mkdir -p $(CACHE_DIR); \
		curl -sSL -o "$(CLOUD_IMAGE)" "$(CLOUD_IMAGE_URL)"; \
		echo "[image] Downloaded to $(CLOUD_IMAGE)"; \
	fi

# --- Infrastructure ---

up: doctor image $(STATE_DIR) ## Provision infrastructure (Terraform)
	@echo "==> Provisioning infrastructure..."
	@# Generate SSH key if needed
	@if [ ! -f "$(SSH_KEY)" ]; then \
		mkdir -p $(STATE_DIR)/creds; \
		ssh-keygen -t ed25519 -f "$(SSH_KEY)" -N "" -C "bosh-lab-mgmt"; \
	fi
	@# Inject SSH pubkey into cloud-init
	@PUB_KEY=$$(cat "$(SSH_KEY).pub"); \
	sed "s|ssh_authorized_keys: \[\]|ssh_authorized_keys:\n      - $$PUB_KEY|" \
		"$(CLOUD_INIT)" > "$(STATE_DIR)/mgmt-cloudinit.yaml"
	@# Run Terraform
	cd $(TF_ENV) && terraform init -input=false
	cd $(TF_ENV) && terraform apply -auto-approve -input=false \
		-var="cloud_image_path=$(CLOUD_IMAGE)" \
		-var="cloud_init_path=$(STATE_DIR)/mgmt-cloudinit.yaml" \
		-var="state_dir=$(STATE_DIR)"
	@# Fix cloud-init ISO directory permissions for QEMU access
	@chmod 711 /tmp/terraform-provider-libvirt-cloudinit 2>/dev/null || true
	@echo "==> Starting VM..."
	@virsh start bosh-lab-mgmt
	@virsh autostart bosh-lab-mgmt
	@echo "==> Infrastructure provisioned. VM at $(MGMT_IP)."
	@echo "    Run 'make bootstrap' next."

bootstrap: ## Bootstrap BOSH Director + CredHub on mgmt VM
	@echo "==> Running bootstrap..."
	$(REPO_ROOT)/bootstrap/bootstrap.sh
	@echo "==> Bootstrap complete. Run 'make env' to configure your shell."

concourse: ## Deploy Concourse via BOSH
	@echo "==> Deploying Concourse..."
	$(REPO_ROOT)/bootstrap/bootstrap.sh --concourse-only
	@echo "==> Concourse deployed."
	@echo "    Set up SSH tunnel: ssh $(SSH_OPTS) -L 8443:10.245.0.10:443 bosh@$(MGMT_IP)"
	@echo "    Then visit: https://127.0.0.1:8443"

env: ## Print shell exports for bosh/credhub CLIs
	@$(REPO_ROOT)/scripts/env.sh

test: ## Run acceptance tests
	@echo "==> Running acceptance tests..."
	@PASS=0; FAIL=0; \
	echo "--- Test 1: BOSH Director reachable ---"; \
	if ssh $(SSH_OPTS) bosh@$(MGMT_IP) "bosh -e lab env" 2>/dev/null; then \
		echo "PASS"; PASS=$$((PASS+1)); \
	else \
		echo "FAIL: Cannot reach BOSH Director"; FAIL=$$((FAIL+1)); \
	fi; \
	echo "--- Test 2: CredHub login ---"; \
	if ssh $(SSH_OPTS) bosh@$(MGMT_IP) "/home/bosh/bootstrap/remote/credhub-smoke.sh" 2>/dev/null; then \
		echo "PASS"; PASS=$$((PASS+1)); \
	else \
		echo "FAIL: CredHub smoke test failed"; FAIL=$$((FAIL+1)); \
	fi; \
	echo "--- Test 3: Concourse deployment exists ---"; \
	if ssh $(SSH_OPTS) bosh@$(MGMT_IP) "bosh -e lab -d concourse instances" 2>/dev/null; then \
		echo "PASS"; PASS=$$((PASS+1)); \
	else \
		echo "FAIL: Concourse deployment not found"; FAIL=$$((FAIL+1)); \
	fi; \
	echo ""; \
	echo "Results: $$PASS passed, $$FAIL failed"; \
	[ $$FAIL -eq 0 ]

status: ## Show lab status
	@$(REPO_ROOT)/scripts/status.sh

logs: ## Tail bootstrap logs
	@$(REPO_ROOT)/scripts/logs.sh

down: ## Destroy infrastructure (keeps state for re-bootstrap)
	@echo "==> Tearing down infrastructure..."
	@echo "    State in ./state is preserved. Use 'make reset' to wipe everything."
	cd $(TF_ENV) && terraform destroy -auto-approve -input=false \
		-var="cloud_image_path=$(CLOUD_IMAGE)" \
		-var="cloud_init_path=$(STATE_DIR)/mgmt-cloudinit.yaml" \
		-var="state_dir=$(STATE_DIR)" \
		2>/dev/null || echo "    Terraform state may be missing. Checking virsh..."
	@# Belt-and-suspenders: also clean via virsh
	virsh destroy bosh-lab-mgmt 2>/dev/null || true
	virsh undefine bosh-lab-mgmt --remove-all-storage 2>/dev/null || true
	@echo "==> Infrastructure destroyed. State preserved in ./state."

reset: ## DANGEROUS: Wipe ALL state and destroy VMs
	@echo ""
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "!  WARNING: This will destroy ALL lab state.      !"
	@echo "!  Director credentials, certs, and caches will   !"
	@echo "!  be permanently deleted.                        !"
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo ""
	@read -p "Type 'yes-destroy-everything' to confirm: " confirm; \
	if [ "$$confirm" = "yes-destroy-everything" ]; then \
		$(REPO_ROOT)/scripts/reset.sh; \
	else \
		echo "Aborted."; \
	fi

doctor: ## Check host prerequisites
	@echo "==> Checking prerequisites..."
	@ERRORS=0; \
	echo "--- KVM ---"; \
	if [ -e /dev/kvm ]; then echo "  OK: /dev/kvm exists"; \
	else echo "  FAIL: /dev/kvm not found. Enable KVM in BIOS."; ERRORS=$$((ERRORS+1)); fi; \
	echo "--- libvirt ---"; \
	if command -v virsh >/dev/null 2>&1; then echo "  OK: virsh found"; \
	else echo "  FAIL: virsh not found. Install libvirt-daemon-system."; ERRORS=$$((ERRORS+1)); fi; \
	if systemctl is-active --quiet libvirtd 2>/dev/null; then echo "  OK: libvirtd running"; \
	else echo "  FAIL: libvirtd not running. Run: sudo systemctl start libvirtd"; ERRORS=$$((ERRORS+1)); fi; \
	echo "--- Terraform ---"; \
	if command -v terraform >/dev/null 2>&1; then echo "  OK: terraform found ($$(terraform version -json 2>/dev/null | jq -r .terraform_version 2>/dev/null || terraform version | head -1))"; \
	else echo "  FAIL: terraform not found. Install terraform >= 1.13."; ERRORS=$$((ERRORS+1)); fi; \
	echo "--- SSH ---"; \
	if command -v ssh >/dev/null 2>&1; then echo "  OK: ssh found"; \
	else echo "  FAIL: ssh not found."; ERRORS=$$((ERRORS+1)); fi; \
	echo "--- Memory ---"; \
	TOTAL_MEM=$$(free -g | awk '/^Mem:/{print $$2}'); \
	if [ "$$TOTAL_MEM" -ge 32 ]; then echo "  OK: $${TOTAL_MEM}GB RAM (>= 32GB recommended)"; \
	else echo "  WARN: $${TOTAL_MEM}GB RAM. 32GB+ recommended for full lab."; fi; \
	echo "--- Disk ---"; \
	AVAIL_DISK=$$(df -BG / | awk 'NR==2{print $$4}' | tr -d 'G'); \
	if [ "$$AVAIL_DISK" -ge 100 ]; then echo "  OK: $${AVAIL_DISK}GB available (>= 100GB recommended)"; \
	else echo "  WARN: $${AVAIL_DISK}GB available. 100GB+ recommended."; fi; \
	echo "--- CPU ---"; \
	CPUS=$$(nproc); \
	if [ "$$CPUS" -ge 8 ]; then echo "  OK: $$CPUS threads (>= 8 recommended)"; \
	else echo "  WARN: $$CPUS threads. 8+ recommended."; fi; \
	echo "--- QEMU security ---"; \
	if sudo -n grep -q '^security_driver = "none"' /etc/libvirt/qemu.conf 2>/dev/null; then \
		echo "  OK: security_driver = none (lab mode)"; \
	elif sudo -n cat /etc/libvirt/qemu.conf 2>/dev/null | grep -q 'security_driver = "none"'; then \
		echo "  OK: security_driver = none (lab mode)"; \
	else \
		echo "  WARN: Cannot verify QEMU security config (needs sudo)."; \
		echo "        If VM fails to start, run: make setup"; \
	fi; \
	echo "--- State dir ---"; \
	if [ -d "$(STATE_DIR)" ]; then echo "  OK: ./state exists"; \
	else echo "  INFO: ./state does not exist (will be created on 'make up')"; fi; \
	if [ -f "$(STATE_DIR)/vars-store.yml" ]; then echo "  OK: vars-store.yml present"; \
	else echo "  INFO: No vars-store.yml (first run or after reset)"; fi; \
	echo ""; \
	if [ $$ERRORS -gt 0 ]; then \
		echo "RESULT: $$ERRORS critical issue(s) found. Fix before proceeding."; \
		exit 1; \
	else \
		echo "RESULT: All prerequisites met."; \
	fi
