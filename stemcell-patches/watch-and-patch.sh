#!/usr/bin/env bash
# watch-and-patch.sh — Watches for grootfs stemcell volume creation,
# then applies Noble stemcell patches automatically.
#
# Runs in the background alongside bosh create-env. Exits after patching.
# The patches fix Noble stemcell (1.215) issues in Garden containers:
# - Missing runsvdir-start (Noble uses systemd, but Garden needs runit)
# - BPM Go binary incompatible with cgroup2 (replaced by shell shim)
# - Missing monit runit service definitions
#
# Usage: ./watch-and-patch.sh &

set -uo pipefail

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOLUMES_DIR="/var/lib/garden/grootfs/store/volumes"
LOG="/home/bosh/state/patch-stemcell.log"
TIMEOUT=1200  # 20 minutes max

log() { echo "[patch-watcher $(date '+%H:%M:%S')] $*" >> "$LOG"; }

log "Started. Watching ${VOLUMES_DIR} for stemcell volumes..."
log "Patch directory: ${PATCH_DIR}"

ELAPSED=0
PATCHED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
  # Check if any volume directories exist
  if [ -d "$VOLUMES_DIR" ]; then
    for vol in "$VOLUMES_DIR"/*/; do
      [ -d "$vol" ] || continue

      # Skip if already patched (sentinel file)
      if [ -f "${vol}.noble-patched" ]; then
        continue
      fi

      # Verify this looks like a stemcell rootfs
      if [ -d "${vol}usr" ] && [ -d "${vol}etc" ]; then
        log "Found stemcell volume: ${vol}"
        log "Applying patches..."

        "$PATCH_DIR/apply-patches.sh" "$vol" >> "$LOG" 2>&1
        RC=$?

        if [ $RC -eq 0 ]; then
          touch "${vol}.noble-patched"
          log "Patches applied successfully."
          PATCHED=$((PATCHED + 1))
        else
          log "WARNING: apply-patches.sh exited with rc=$RC"
        fi
      fi
    done
  fi

  # If we've patched at least one volume, wait a bit for any additional
  # volumes (unlikely, but safe), then exit
  if [ $PATCHED -gt 0 ]; then
    sleep 5
    # Check one more time for new volumes
    NEW_FOUND=0
    if [ -d "$VOLUMES_DIR" ]; then
      for vol in "$VOLUMES_DIR"/*/; do
        [ -d "$vol" ] || continue
        [ -f "${vol}.noble-patched" ] && continue
        if [ -d "${vol}usr" ] && [ -d "${vol}etc" ]; then
          "$PATCH_DIR/apply-patches.sh" "$vol" >> "$LOG" 2>&1
          touch "${vol}.noble-patched"
          NEW_FOUND=$((NEW_FOUND + 1))
        fi
      done
    fi
    log "Patched ${PATCHED} volume(s). Exiting."
    exit 0
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

log "TIMEOUT: No volumes found after ${TIMEOUT}s. Exiting."
exit 1
