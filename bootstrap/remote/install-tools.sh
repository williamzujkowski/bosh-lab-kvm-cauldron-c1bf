#!/usr/bin/env bash
# install-tools.sh — Runs INSIDE the mgmt VM
# Installs bosh-cli, credhub-cli, and fly at pinned versions.
# Idempotent: skips if correct version already installed.

set -euo pipefail

# Version pins
BOSH_CLI_VERSION="7.9.17"
CREDHUB_CLI_VERSION="2.9.53"
FLY_VERSION="8.0.1"

echo "[install-tools] Checking bosh-cli..."
if command -v bosh &>/dev/null && bosh --version 2>/dev/null | grep -q "${BOSH_CLI_VERSION}"; then
  echo "[install-tools] bosh-cli ${BOSH_CLI_VERSION} already installed."
else
  echo "[install-tools] Installing bosh-cli ${BOSH_CLI_VERSION}..."
  curl -sSL "https://github.com/cloudfoundry/bosh-cli/releases/download/v${BOSH_CLI_VERSION}/bosh-cli-${BOSH_CLI_VERSION}-linux-amd64" -o /tmp/bosh
  chmod +x /tmp/bosh
  sudo mv /tmp/bosh /usr/local/bin/bosh
  echo "[install-tools] bosh-cli installed: $(bosh --version)"
fi

echo "[install-tools] Checking credhub-cli..."
if command -v credhub &>/dev/null && credhub --version 2>/dev/null | grep -q "${CREDHUB_CLI_VERSION}"; then
  echo "[install-tools] credhub-cli ${CREDHUB_CLI_VERSION} already installed."
else
  echo "[install-tools] Installing credhub-cli ${CREDHUB_CLI_VERSION}..."
  curl -sSL "https://github.com/cloudfoundry/credhub-cli/releases/download/${CREDHUB_CLI_VERSION}/credhub-linux-amd64-${CREDHUB_CLI_VERSION}.tgz" -o /tmp/credhub.tgz
  mkdir -p /tmp/credhub-extract
  tar xzf /tmp/credhub.tgz -C /tmp/credhub-extract
  sudo mv /tmp/credhub-extract/credhub /usr/local/bin/credhub
  rm -rf /tmp/credhub.tgz /tmp/credhub-extract
  echo "[install-tools] credhub-cli installed: $(credhub --version)"
fi

echo "[install-tools] Checking fly CLI..."
if command -v fly &>/dev/null && fly --version 2>/dev/null | grep -q "${FLY_VERSION}"; then
  echo "[install-tools] fly ${FLY_VERSION} already installed."
else
  echo "[install-tools] Installing fly ${FLY_VERSION}..."
  curl -sSL "https://github.com/concourse/concourse/releases/download/v${FLY_VERSION}/fly-${FLY_VERSION}-linux-amd64.tgz" -o /tmp/fly.tgz
  mkdir -p /tmp/fly-extract
  tar xzf /tmp/fly.tgz -C /tmp/fly-extract
  sudo mv /tmp/fly-extract/fly /usr/local/bin/fly
  rm -rf /tmp/fly.tgz /tmp/fly-extract
  echo "[install-tools] fly installed: $(fly --version)"
fi

echo "[install-tools] All tools installed."
