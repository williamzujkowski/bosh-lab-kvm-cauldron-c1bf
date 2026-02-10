variable "vm_name" {
  type = string
}

variable "vcpu" {
  type = number
}

variable "memory_mb" {
  type = number
}

variable "disk_gb" {
  type = number
}

variable "static_ip" {
  type = string
}

variable "network_id" {
  type = string
}

variable "cloud_image_path" {
  type = string
}

variable "cloud_init_path" {
  type = string
}

variable "state_dir" {
  type = string
}

variable "pool_path" {
  type = string
}

# Storage pool for VM disks
resource "libvirt_pool" "bosh_lab" {
  name = "bosh-lab"
  type = "dir"
  path = var.pool_path
}

# Base image volume (uploaded once from cloud image)
resource "libvirt_volume" "ubuntu_base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = libvirt_pool.bosh_lab.name
  source = var.cloud_image_path
  format = "qcow2"
}

# Root disk (COW clone of base, resized)
resource "libvirt_volume" "mgmt_root" {
  name           = "${var.vm_name}-root.qcow2"
  pool           = libvirt_pool.bosh_lab.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
  size           = var.disk_gb * 1024 * 1024 * 1024
}

# Cloud-init ISO
resource "libvirt_cloudinit_disk" "mgmt_init" {
  name      = "${var.vm_name}-cloudinit.iso"
  pool      = libvirt_pool.bosh_lab.name
  user_data = file(var.cloud_init_path)
}

# Management VM
resource "libvirt_domain" "mgmt" {
  name   = var.vm_name
  memory = var.memory_mb
  vcpu   = var.vcpu

  cloudinit = libvirt_cloudinit_disk.mgmt_init.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = var.network_id
    addresses      = [var.static_ip]
    wait_for_lease = false
  }

  disk {
    volume_id = libvirt_volume.mgmt_root.id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    listen_address = "127.0.0.1"
    autoport    = true
  }

  # Share state directory with VM via 9p filesystem
  filesystem {
    source   = var.state_dir
    target   = "state"
    readonly = false
    accessmode = "mapped"
  }

  provisioner "local-exec" {
    command = "echo 'Mgmt VM ${var.vm_name} created at ${var.static_ip}'"
  }
}

output "vm_id" {
  value = libvirt_domain.mgmt.id
}

output "vm_ip" {
  value = var.static_ip
}
