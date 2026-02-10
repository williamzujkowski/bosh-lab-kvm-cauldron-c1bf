#!/usr/bin/env bash
# Retry helper with exponential backoff
# Usage: source bootstrap/lib/retry.sh
#        retry 5 2 "some command"

retry() {
  local max_attempts="$1"
  local delay="$2"
  shift 2
  local cmd="$*"
  local attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    if eval "$cmd"; then
      return 0
    fi
    log_warn "Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
    sleep "$delay"
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done

  log_error "Command failed after $max_attempts attempts: $cmd"
  return 1
}
