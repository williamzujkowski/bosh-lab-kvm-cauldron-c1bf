# bosh-lab-kvm-cauldron-c1bf

One-command BOSH + CredHub + Concourse local lab on KVM/libvirt. Deterministic, restartable, not sloppy.

**Target audience:** Developers with a Linux laptop (64GB RAM, 16 threads) who want to run real BOSH infrastructure locally.

## What You Get

- A BOSH Director with CredHub and UAA, running in a KVM VM
- Concourse CI deployed via BOSH (not Docker)
- A sample pipeline that deploys and tears down a BOSH workload
- Everything local-only by default (no LAN exposure)
- Cattle-pattern mgmt VM: destroy and recreate without losing state

## Prerequisites

| Requirement | Minimum | Recommended |
|---|---|---|
| OS | Linux with KVM/libvirt | Ubuntu 22.04+ |
| RAM | 32 GB | 64 GB |
| CPU | 8 threads | 16 threads |
| Disk | 100 GB free | 200 GB free |
| Terraform | 1.13+ | 1.14.4 |

```bash
# Install libvirt
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
# Log out and back in

# Verify KVM
ls /dev/kvm

# Check everything
make doctor
```

## Quickstart

```bash
# 1. Clone
git clone https://github.com/williamzujkowski/bosh-lab-kvm-cauldron-c1bf.git
cd bosh-lab-kvm-cauldron-c1bf

# 2. Check prerequisites
make doctor

# 3. Provision infrastructure + bootstrap BOSH Director
make up
make bootstrap

# 4. Verify
eval "$(./scripts/env.sh)"
bosh -e 10.245.0.2 env
credhub login  # Uses env vars from above
credhub find

# 5. Deploy Concourse
make concourse

# 6. Access Concourse UI (in a separate terminal)
eval "$(./scripts/env.sh)"
concourse-tunnel   # SSH tunnel to Concourse
# Visit https://127.0.0.1:8443

# 7. Set up a pipeline
fly -t lab login -c https://127.0.0.1:8443 -u admin -p $(bosh int state/creds/concourse-vars.yml --path /admin_password) -k
fly -t lab set-pipeline -p sample -c pipelines/sample/pipeline.yml
fly -t lab unpause-pipeline -p sample
fly -t lab trigger-job -j sample/deploy-and-teardown
```

## Resource Sizing Knobs

Edit `terraform/envs/laptop/terraform.tfvars`:

| Variable | Default | Description |
|---|---|---|
| `mgmt_vm_vcpu` | 4 | CPU cores for mgmt VM |
| `mgmt_vm_memory_mb` | 8192 | RAM in MB for mgmt VM |
| `mgmt_vm_disk_gb` | 80 | Root disk in GB |

**For 32GB RAM laptops:** Reduce `mgmt_vm_memory_mb` to `4096`. Concourse compilation will be slower but functional.

**For 128GB RAM machines:** Increase to `16384` and `mgmt_vm_vcpu=8` for faster compilation.

## Makefile Targets

| Target | Description |
|---|---|
| `make up` | Provision VM and network via Terraform |
| `make bootstrap` | Bootstrap BOSH Director + CredHub (idempotent) |
| `make concourse` | Deploy Concourse via BOSH |
| `make env` | Print shell exports for CLI tools |
| `make test` | Run acceptance tests |
| `make status` | Show lab component status |
| `make logs` | Tail bootstrap logs |
| `make down` | Destroy VM (preserves state for re-bootstrap) |
| `make reset` | **DANGEROUS:** Wipe all state and destroy everything |
| `make doctor` | Check host prerequisites |

## Restarting After Reboot

```bash
virsh start bosh-lab-mgmt   # If VM didn't auto-start
make bootstrap               # Idempotent — converges without recreating
```

## Version Pins

| Component | Version |
|---|---|
| bosh-cli | 7.9.17 |
| credhub-cli | 2.9.53 |
| bosh-deployment | commit `faf834a` |
| libvirt CPI | v4.1 |
| Concourse release | 8.0.1 |
| Stemcell | ubuntu-jammy/1.1044 |
| fly CLI | 8.0.1 |
| Ubuntu cloud image | 22.04 LTS (Jammy) |
| Terraform | >= 1.13.0 |
| terraform-provider-libvirt | ~> 0.9.2 |

## Architecture

See [docs/design.md](design.md) for the full design document including:
- Libvirt network design (10.245.0.0/24, NAT, no DHCP)
- CPI configuration (a2geek/libvirt-bosh-cpi)
- CredHub access model
- Security exposure defaults
- Version pinning strategy

## Security

See [docs/security-notes.md](security-notes.md). Key points:

- **Local-only by default.** Nothing exposed to LAN.
- **No committed secrets.** `./state/` is gitignored.
- **TLS everywhere.** All inter-component communication uses TLS.
- **Not for production.** This is a developer lab.

## Known Limitations

These are real, not hedging:

1. **The libvirt CPI is a community project** ([a2geek/libvirt-bosh-cpi](https://github.com/a2geek/libvirt-bosh-cpi)). It supports manual networks only. No dynamic or VIP networks. Disk resize support was added in v4 but may have edge cases.

2. **Nested virtualization required.** BOSH-managed VMs run as KVM guests inside the mgmt VM. Your host CPU must support and have nested KVM enabled. Performance will be lower than bare-metal BOSH.

3. **First bootstrap is slow.** Downloading stemcells, releases, and compiling packages takes 30-60 minutes on first run. Subsequent runs use caches.

4. **No automated SHA verification.** Downloaded binaries (bosh-cli, credhub-cli, cloud images) are fetched over HTTPS but checksums are not verified programmatically. This is a known gap.

5. **9p filesystem sharing is fragile.** The host-to-VM state sharing via 9p/virtio works on most kernels but can fail on older hosts. If it doesn't work, the bootstrap script falls back to SCP.

6. **Certificate rotation is destroy-and-rebuild.** No in-place cert rotation for the MVP. `make reset && make up && make bootstrap` is the rotation procedure.

7. **Single management VM.** The director, CredHub, UAA, and nested VMs all share one VM. Resource contention is real on < 32GB RAM.

8. **bosh-deployment pin may drift.** The pinned commit on bosh-deployment's master may reference release versions that get removed from bosh.io. If this happens, update the pin.

9. **Linux-only.** No macOS or Windows support. This uses KVM, libvirt, and 9p — none of which exist on other platforms.

10. **No HA.** Single director, single Concourse web, single DB. This is a lab, not production.

## Troubleshooting

See [docs/troubleshooting.md](troubleshooting.md) for detailed remediation steps for common failures.

## License

MIT
