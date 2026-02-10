#!/usr/bin/env bash
# fix-garden-nested.sh — Patches Garden config inside the BOSH container
# for nested container support.
#
# Runs on the mgmt VM. Uses runc exec to enter the BOSH director container
# and fix issues preventing nested container creation:
#
# 1. init-bin: BOSH release template sets /sbin/init (systemd), but Garden
#    needs its own init binary at /var/vcap/packages/guardian/bin/init
# 2. cgroup2: The kernel mounts cgroup2 on top of /sys/fs/cgroup, hiding
#    the v1 controllers that Garden's runc expects
# 3. AppArmor: garden-default profile may not work in nested containers
# 4. warden CPI: start_containers_with_systemd must be false since containers
#    don't run systemd — the CPI must explicitly start the BOSH agent
#
# Usage: sudo ./fix-garden-nested.sh

set -euo pipefail

# Find the running BOSH director container
CONTAINER_ID=$(sudo /usr/sbin/runc list 2>/dev/null | awk '/running/ {print $1}' | head -1)
if [ -z "$CONTAINER_ID" ]; then
  echo "[fix-garden] ERROR: No running runc container found."
  exit 1
fi

echo "[fix-garden] Found BOSH container: ${CONTAINER_ID}"

# Get container PID for nsenter (faster than runc exec for simple commands)
CONTAINER_PID=$(sudo /usr/sbin/runc state "$CONTAINER_ID" 2>/dev/null | grep '"pid"' | grep -o '[0-9]*')
echo "[fix-garden] Container PID: ${CONTAINER_PID}"

run_in_container() {
  sudo nsenter -t "$CONTAINER_PID" -m -u -i -n -p -- /bin/bash -c "$1"
}

# 1. Fix init-bin in Garden config
echo "[fix-garden] Checking Garden init-bin config..."
CURRENT_INIT=$(run_in_container "grep 'init-bin' /var/vcap/jobs/garden/config/config.ini 2>/dev/null || echo 'not found'")
if echo "$CURRENT_INIT" | grep -q '/sbin/init'; then
  echo "[fix-garden] Fixing init-bin: /sbin/init -> guardian init"
  run_in_container "sed -i 's|init-bin = /sbin/init|init-bin = /var/vcap/packages/guardian/bin/init|' /var/vcap/jobs/garden/config/config.ini"
else
  echo "[fix-garden] init-bin already correct: ${CURRENT_INIT}"
fi

# 2. Fix cgroup2 overlay hiding v1 controllers
echo "[fix-garden] Checking cgroup setup..."
CGROUP_TYPE=$(run_in_container "stat -f -c '%T' /sys/fs/cgroup 2>/dev/null || echo 'unknown'")
if [ "$CGROUP_TYPE" = "cgroup2fs" ]; then
  echo "[fix-garden] Unmounting cgroup2 overlay to expose v1 controllers..."
  run_in_container "umount /sys/fs/cgroup 2>/dev/null || true"
  # Verify v1 controllers are now visible
  V1_COUNT=$(run_in_container "ls -d /sys/fs/cgroup/*/ 2>/dev/null | wc -l")
  echo "[fix-garden] v1 cgroup controllers visible: ${V1_COUNT}"
fi

# Create garden cgroup directories in all v1 controllers
echo "[fix-garden] Ensuring garden cgroup directories..."
run_in_container '
for controller in /sys/fs/cgroup/*/; do
  [ -d "$controller" ] || continue
  name=$(basename "$controller")
  if [ ! -d "$controller/garden" ]; then
    mkdir -p "$controller/garden" 2>/dev/null || true
  fi
done
'

# 3. Disable AppArmor profile (may not work nested)
echo "[fix-garden] Checking AppArmor config..."
APPARMOR_LINE=$(run_in_container "grep -n 'apparmor' /var/vcap/jobs/garden/config/config.ini 2>/dev/null | head -1 || echo ''")
if echo "$APPARMOR_LINE" | grep -q 'apparmor = garden-default'; then
  echo "[fix-garden] Disabling AppArmor profile for nested containers..."
  run_in_container "sed -i 's/^  apparmor = garden-default/  ; apparmor disabled for nested containers/' /var/vcap/jobs/garden/config/config.ini"
fi

# 4. Fix warden CPI start_containers_with_systemd
# The CPI defaults to starting containers with systemd, but our containers
# don't run systemd (they use Guardian's init). Set to false so the CPI
# explicitly runs the agent start script inside containers.
echo "[fix-garden] Checking warden CPI config..."
CPI_SYSTEMD=$(run_in_container "grep -o 'start_containers_with_systemd\":true' /var/vcap/jobs/warden_cpi/config/cpi.json 2>/dev/null || echo ''")
if [ -n "$CPI_SYSTEMD" ]; then
  echo "[fix-garden] Fixing CPI: disabling start_containers_with_systemd"
  run_in_container 'sed -i "s/\"start_containers_with_systemd\":true/\"start_containers_with_systemd\":false/" /var/vcap/jobs/warden_cpi/config/cpi.json'
  run_in_container "/var/vcap/bosh/bin/monit restart warden_cpi"
  sleep 3
else
  echo "[fix-garden] CPI start_containers_with_systemd already false"
fi

# 5. Restart Garden to pick up config changes
echo "[fix-garden] Restarting Garden..."
run_in_container "/var/vcap/bosh/bin/monit restart garden"
sleep 5

# Wait for Garden to be ready
echo "[fix-garden] Waiting for Garden..."
for i in $(seq 1 30); do
  if run_in_container "curl -s http://127.0.0.1:7777/containers" 2>/dev/null | grep -q 'Handles'; then
    echo "[fix-garden] Garden is ready."
    break
  fi
  sleep 2
done

# 6. Verify nested container creation works
echo "[fix-garden] Testing nested container creation..."
CREATE_RESULT=$(run_in_container 'curl -s -X POST http://127.0.0.1:7777/containers -H "Content-Type: application/json" -d "{\"handle\": \"fix-garden-test\"}" 2>&1')
if echo "$CREATE_RESULT" | grep -q 'fix-garden-test'; then
  echo "[fix-garden] Container creation works!"
  # Clean up test container
  run_in_container 'curl -s -X DELETE http://127.0.0.1:7777/containers/fix-garden-test' >/dev/null 2>&1
else
  echo "[fix-garden] WARNING: Container creation test failed: ${CREATE_RESULT}"
  exit 1
fi

echo "[fix-garden] All fixes applied successfully."
