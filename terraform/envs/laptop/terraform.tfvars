# Laptop environment — adjust these knobs for your hardware
# See README.md for resource sizing guidance

libvirt_uri = "qemu:///system"

# Network
network_name    = "bosh-lab"
network_cidr    = "10.245.0.0/24"
network_gateway = "10.245.0.1"

# Management VM sizing
mgmt_vm_name      = "bosh-lab-mgmt"
mgmt_vm_vcpu      = 4
mgmt_vm_memory_mb = 8192
mgmt_vm_disk_gb   = 80
mgmt_vm_ip        = "10.245.0.2"

# Paths — set by Makefile, override here if needed
# cloud_image_path = "./state/cache/noble-server-cloudimg-amd64.img"
# cloud_init_path  = "./cloud-init/mgmt.yaml"
# state_dir        = "./state"
# pool_path        = "/var/lib/libvirt/images/bosh-lab"
