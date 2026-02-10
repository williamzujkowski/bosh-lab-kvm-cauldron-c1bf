# Troubleshooting

## `make doctor` fails

### `/dev/kvm` not found

**Cause:** KVM is not enabled in BIOS, or the `kvm` kernel modules are not loaded.

**Fix:**
```bash
# Check if KVM modules are loaded
lsmod | grep kvm

# Load them manually
sudo modprobe kvm_intel   # Intel CPUs
sudo modprobe kvm_amd     # AMD CPUs

# If modules don't exist, enable virtualization in BIOS/UEFI settings.
```

### `virsh` not found

**Cause:** libvirt is not installed.

**Fix:**
```bash
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
# Log out and back in for group membership to take effect
```

### `libvirtd` not running

**Fix:**
```bash
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
```

### Terraform not found

**Fix:** Install via [tfenv](https://github.com/tfutils/tfenv) or direct download:
```bash
# Using tfenv
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
tfenv install 1.9.8
tfenv use 1.9.8
```

---

## `make up` fails

### "Could not open '/var/lib/libvirt/images/bosh-lab'"

**Cause:** The storage pool directory doesn't exist or libvirt doesn't have permissions.

**Fix:**
```bash
sudo mkdir -p /var/lib/libvirt/images/bosh-lab
sudo chown libvirt-qemu:kvm /var/lib/libvirt/images/bosh-lab
```

### "Error creating libvirt network: already exists"

**Cause:** A previous `bosh-lab` network exists from a failed run.

**Fix:**
```bash
virsh net-destroy bosh-lab
virsh net-undefine bosh-lab
make up
```

### Cloud image download fails

**Cause:** Network issue or Ubuntu mirror down.

**Fix:**
```bash
# Download manually
wget -O state/cache/jammy-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
make up
```

---

## `make bootstrap` fails

### "Connection refused" to mgmt VM

**Cause:** VM hasn't finished booting, or cloud-init hasn't installed SSH.

**Fix:**
```bash
# Check VM is running
virsh list --all

# Check VM console for boot progress
virsh console bosh-lab-mgmt

# Wait longer — cloud-init can take 2-5 minutes on first boot
# The bootstrap script retries 30 times with 5-second delays
```

### "Permission denied (publickey)"

**Cause:** SSH key wasn't injected into cloud-init properly.

**Fix:**
```bash
# Verify the key was generated
ls -la state/creds/mgmt_ssh*

# Verify cloud-init has the key
grep ssh_authorized_keys state/mgmt-cloudinit.yaml

# If missing, recreate:
make down
rm -f state/creds/mgmt_ssh*
make up
```

### `bosh create-env` fails

**Cause:** Many possible reasons. Check the log.

**Fix:**
```bash
# Read the full log
cat state/logs/create-director.log

# Common issues:
# 1. Nested KVM not enabled — check /dev/kvm inside the VM
# 2. Network conflict — another 10.245.0.0/24 network exists
# 3. Disk space — need ~40GB free inside the VM
# 4. Memory — director needs ~4GB RAM
```

### 9p mount fails inside VM

**Cause:** The 9p kernel module may not be loaded, or the filesystem tag doesn't match.

**Fix:**
```bash
# SSH into the VM and check
ssh -i state/creds/mgmt_ssh bosh@10.245.0.2

# Inside VM:
sudo mount -t 9p -o trans=virtio,version=9p2000.L state /mnt/state
ls /mnt/state

# If 9p isn't available, the bootstrap script will fall back to SCP
# for copying state files back and forth.
```

---

## `make concourse` fails

### "Stemcell not found"

**Cause:** The stemcell version doesn't match what's available on bosh.io.

**Fix:**
```bash
# Check available stemcells
bosh -e lab stemcells

# Upload manually if needed
bosh -e lab upload-stemcell \
  "https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent?v=1.717"
```

### Concourse deploy times out

**Cause:** Compilation takes a long time on limited resources. Default timeout may be too short.

**Fix:**
```bash
# Check deployment status
bosh -e lab -d concourse instances
bosh -e lab tasks --recent

# Compilation can take 20-40 minutes on first deploy.
# Subsequent deploys reuse compiled packages.
```

---

## `make test` fails

### Test 1 fails (BOSH Director unreachable)

Check `make status` and `make bootstrap`. The director may need to be re-bootstrapped after a VM restart.

### Test 2 fails (CredHub smoke test)

CredHub credentials may have rotated. Re-extract from vars-store:
```bash
bosh int state/vars-store.yml --path /credhub_admin_client_secret
```

### Test 3 fails (Concourse not deployed)

Run `make concourse` to deploy Concourse.

---

## General Tips

### Reboot recovery

After host reboot:
```bash
# VMs should auto-start (libvirt autostart is enabled on the network)
# But the VM may need manual start:
virsh start bosh-lab-mgmt

# Then re-bootstrap (idempotent, won't recreate director):
make bootstrap
```

### Freeing disk space

```bash
# Check what's using space
du -sh state/*

# Clear the release/stemcell cache (will re-download next deploy)
rm -rf state/cache/*.tgz

# Clear logs
rm -f state/logs/*.log
```

### Checking resource usage

```bash
# VM resources
virsh dominfo bosh-lab-mgmt

# Host resources
free -h
df -h
nproc
```
