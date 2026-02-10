#!/usr/bin/env bash
# Logging helpers for bootstrap scripts
# Usage: source bootstrap/lib/log.sh

_LOG_PREFIX="[bosh-lab]"

log_info() {
  echo -e "${_LOG_PREFIX} \033[0;32mINFO\033[0m  $*"
}

log_warn() {
  echo -e "${_LOG_PREFIX} \033[0;33mWARN\033[0m  $*" >&2
}

log_error() {
  echo -e "${_LOG_PREFIX} \033[0;31mERROR\033[0m $*" >&2
}

log_step() {
  echo ""
  echo -e "${_LOG_PREFIX} \033[1;34m==>\033[0m $*"
}

log_fatal() {
  log_error "$@"
  exit 1
}
