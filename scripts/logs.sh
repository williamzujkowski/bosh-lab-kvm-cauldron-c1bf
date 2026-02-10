#!/usr/bin/env bash
# logs.sh — Tail bootstrap and runtime logs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${REPO_ROOT}/state/logs"

if [ ! -d "$LOG_DIR" ]; then
  echo "No logs directory found. Run 'make bootstrap' first."
  exit 1
fi

LOG_FILES=$(find "$LOG_DIR" -name "*.log" -type f 2>/dev/null)
if [ -z "$LOG_FILES" ]; then
  echo "No log files found in ${LOG_DIR}."
  exit 0
fi

echo "=== Log files in ${LOG_DIR} ==="
ls -lt "$LOG_DIR"/*.log 2>/dev/null
echo ""
echo "=== Tailing most recent logs (Ctrl+C to stop) ==="
# shellcheck disable=SC2086
tail -f $LOG_FILES
