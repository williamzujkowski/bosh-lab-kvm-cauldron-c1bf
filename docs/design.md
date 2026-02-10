# Design Document — bosh-lab-kvm-cauldron-c1bf

**Repository:** `bosh-lab-kvm-cauldron-c1bf`
**Purpose:** One-command BOSH + CredHub + Concourse local lab on KVM/libvirt

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Developer Laptop (Linux, 64GB RAM, 16 threads)      │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │  KVM / libvirt                                  │ │
│  │                                                 │ │
│  │  Network: bosh-lab (10.245.0.0/24, NAT)         │ │
│  │  ┌─────────────────────────────────────────┐    │ │
│  │  │  Mgmt VM (10.245.0.2)                   │    │ │
│  │  │  Ubuntu 22.04 LTS                       │    │ │
│  │  │  ┌──────────────────────────────────┐   │    │ │
│  │  │  │  BOSH Director + CredHub + UAA   │   │    │ │
│  │  │  │  (bosh create-env, bosh-lite)    │   │    │ │
│  │  │  └──────────────────────────────────┘   │    │ │
│  │  │                                         │    │ │
│  │  │  BOSH-managed VMs (containers/VMs):     │    │ │
│  │  │  ┌────────────┐ ┌────────────────────┐  │    │ │
│  │  │  │ Concourse  │ │ User deployments   │  │    │ │
│  │  │  │ web+db+wkr │ │ (zookeeper, etc.)  │  │    │ │
│  │  │  └────────────┘ └────────────────────┘  │    │ │
│  │  └─────────────────────────────────────────┘    │ │
│  │                                                 │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  Host filesystem:                                    │
│  ./state/ ─────────── 9p mount ──────── /mnt/state   │
│    ├─ vars-store.yml  (director creds)               │
│    ├─ creds/          (SSH keys, state files)        │
│    ├─ ca/             (CA certs)                     │
│    ├─ cache/          (stemcells, releases, images)  │
│    ├─ logs/           (bootstrap logs)               │
│    └─ terraform.tfstate                              │
└──────────────────────────────────────────────────────┘
```

## Libvirt Network Design

**Network:** `bosh-lab` — a NAT network on `10.245.0.0/24`.

| IP Range | Purpose |
|---|---|
| 10.245.0.1 | Gateway (libvirt host bridge) |
| 10.245.0.2 | Management VM (BOSH Director) |
| 10.245.0.3-10.245.0.9 | Reserved for future management VMs |
| 10.245.0.10-10.245.0.50 | Static IPs for BOSH deployments (Concourse, etc.) |
| 10.245.0.51-10.245.0.254 | Dynamic pool for compilation VMs |

**DHCP is disabled.** BOSH manages all IP assignment via the CPI. The management VM gets a static IP from Terraform. The gateway provides NAT for outbound internet access (stemcell/release downloads).

**DNS:** The libvirt network provides local DNS resolution. Upstream DNS falls back to `8.8.8.8`.

## CPI Configuration

The lab uses the **libvirt CPI** ([a2geek/libvirt-bosh-cpi](https://github.com/a2geek/libvirt-bosh-cpi) v4.1) to allow BOSH to orchestrate VMs via KVM/libvirt.

**How it works:**
1. Terraform creates the libvirt network and management VM.
2. `bosh create-env` runs inside the mgmt VM, using bosh-deployment with a custom ops file that swaps the VirtualBox CPI for the libvirt CPI.
3. The CPI talks to `qemu:///system` to create/destroy/manage VMs.
4. BOSH-managed VMs (Concourse workers, user deployments) run as nested KVM guests inside the mgmt VM.

**Ops file:** `manifests/director/ops/libvirt-cpi.yml` overrides the CPI release, stemcell source, and cloud provider configuration.

**Limitations:**
- The libvirt CPI is a community project, not an official Cloud Foundry CPI. It supports manual networks only (no dynamic/vip).
- Disk resizing was added in v4 but may have edge cases.
- Nested virtualization must be enabled on the host.

## CredHub Enablement

CredHub is deployed as part of the BOSH Director via the `credhub.yml` ops file from bosh-deployment.

**Access model:**
- CredHub runs on the director VM at `https://10.245.0.2:8844`.
- Authentication is via UAA (deployed alongside, ops file `uaa.yml`).
- The `credhub-admin` client is auto-generated in `vars-store.yml`.
- BOSH deployments can reference CredHub variables using `((variable_name))` syntax.

**Credential flow:**
1. `vars-store.yml` stores all generated credentials (passwords, certs, keys).
2. This file lives on the host at `./state/vars-store.yml` (persists across VM rebuilds).
3. The 9p mount makes it available inside the VM at `/mnt/state/vars-store.yml`.
4. `credhub login` uses the client secret from vars-store.

## Security Exposure Defaults

**Principle: local-only by default.** Nothing is exposed to the LAN.

| Service | Bind Address | Port | Exposure |
|---|---|---|---|
| BOSH Director | 10.245.0.2 | 25555 | NAT network only |
| CredHub | 10.245.0.2 | 8844 | NAT network only |
| UAA | 10.245.0.2 | 8443 | NAT network only |
| Concourse Web | 10.245.0.10 | 443 | NAT network only |
| VNC (mgmt VM) | 127.0.0.1 | auto | Localhost only |

**To access Concourse from the host browser:** Set up an SSH tunnel:
```bash
ssh -i state/creds/mgmt_ssh -L 8443:10.245.0.10:443 bosh@10.245.0.2
```
Then visit `https://127.0.0.1:8443`.

**To expose to LAN (opt-in):** Modify the libvirt network mode from `nat` to `bridge` and update firewall rules. This is deliberately not automated.

## Version Pinning Strategy

Every external dependency is pinned to a specific version. No `latest` tags.

| Component | Version | Pin Location |
|---|---|---|
| bosh-cli | 7.9.17 | `bootstrap/lib/common.sh`, `bootstrap/remote/install-tools.sh` |
| credhub-cli | 2.9.53 | `bootstrap/lib/common.sh`, `bootstrap/remote/install-tools.sh` |
| bosh-deployment | commit `94a3c51e` | `bootstrap/lib/common.sh`, `bootstrap/remote/create-director.sh` |
| libvirt CPI | v4.1 | `manifests/director/ops/libvirt-cpi.yml` |
| Concourse release | 7.14.1 | `manifests/concourse/concourse.yml` |
| Stemcell | ubuntu-jammy/1.717 | `manifests/concourse/concourse.yml`, cloud-config |
| fly CLI | 7.14.1 | `bootstrap/remote/install-tools.sh` |
| Ubuntu cloud image | jammy (22.04 LTS) | `Makefile` (downloaded to cache) |
| Terraform | >= 1.9.0 | `terraform/versions.tf` |
| terraform-provider-libvirt | ~> 0.8.1 | `terraform/versions.tf` |

**Update process:** Change the version in the pin location, run `make reset && make up && make bootstrap`, verify acceptance tests pass.

## Cattle Pattern

The management VM is disposable. All persistent state lives on the host at `./state/`:
- `vars-store.yml` — all director credentials
- `creds/director-state.json` — BOSH director state file
- `creds/mgmt_ssh` — SSH key for VM access
- `cache/` — downloaded stemcells, releases, cloud images
- `terraform.tfstate` — infrastructure state

**Rebuild workflow:**
1. `make down` — destroy the VM (state preserved)
2. `make up` — recreate the VM
3. `make bootstrap` — converge director using existing state

The director will be re-created from `vars-store.yml`, preserving all credentials and deployments.
