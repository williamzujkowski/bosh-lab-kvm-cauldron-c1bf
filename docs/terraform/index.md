# Terraform Reference

This section contains auto-generated documentation for the Terraform
modules and environments in this repository.

Documentation is generated on every push to `main` using
[terraform-docs](https://terraform-docs.io/).

## Structure

```
terraform/
├── envs/
│   └── laptop/          # Laptop environment configuration
│       ├── backend.tf   # Local state backend
│       ├── main.tf      # Module composition
│       ├── variables.tf # Input variables with defaults
│       ├── outputs.tf   # Environment outputs
│       └── versions.tf  # Provider requirements
└── modules/
    ├── libvirt-network/ # NAT network for the BOSH lab
    └── mgmt-vm/        # Management VM (BOSH Director host)
```

## Modules

| Module | Description |
|---|---|
| [libvirt-network](module-libvirt-network.md) | Creates the NAT network (10.245.0.0/24) with DNS, no DHCP |
| [mgmt-vm](module-mgmt-vm.md) | Provisions the management VM with storage pool, cloud-init, and 9p filesystem |

## Environments

| Environment | Description |
|---|---|
| [laptop](env-laptop.md) | Single-machine developer laptop configuration |
