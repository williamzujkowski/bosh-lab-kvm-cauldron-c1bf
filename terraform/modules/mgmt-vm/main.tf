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

variable "network_name" {
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

variable "network_gateway" {
  type = string
}

variable "network_cidr" {
  type = string
}

# Storage pool for VM disks
resource "libvirt_pool" "bosh_lab" {
  name = "bosh-lab"
  type = "dir"
  target = {
    path = var.pool_path
  }
}

# Base image volume (uploaded once from cloud image)
resource "libvirt_volume" "ubuntu_base" {
  name = "${var.vm_name}-base.qcow2"
  pool = libvirt_pool.bosh_lab.name
  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = var.cloud_image_path
    }
  }
}

# Root disk (COW clone of base, resized)
resource "libvirt_volume" "mgmt_root" {
  name     = "${var.vm_name}-root.qcow2"
  pool     = libvirt_pool.bosh_lab.name
  capacity = var.disk_gb * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

# Cloud-init ISO
resource "libvirt_cloudinit_disk" "mgmt_init" {
  name      = "${var.vm_name}-cloudinit.iso"
  user_data = file(var.cloud_init_path)
  meta_data = yamlencode({
    instance-id    = var.vm_name
    local-hostname = var.vm_name
  })
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = {
        match = {
          macaddress = "52:54:00:b0:5e:02"
        }
        addresses = ["${var.static_ip}/${split("/", var.network_cidr)[1]}"]
        routes = [{
          to      = "0.0.0.0/0"
          via     = var.network_gateway
        }]
        nameservers = {
          addresses = [var.network_gateway]
        }
      }
    }
  })
}

# Management VM
resource "libvirt_domain" "mgmt" {
  name        = var.vm_name
  type        = "kvm"
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpu

  os = {
    type = "hvm"
  }

  cpu = {
    mode = "host-passthrough"
  }

  devices = {
    interfaces = [{
      mac = {
        address = "52:54:00:b0:5e:02"
      }
      source = {
        network = {
          network = var.network_name
        }
      }
    }]

    disks = [
      {
        target = {
          dev = "vda"
          bus = "virtio"
        }
        source = {
          volume = {
            pool   = libvirt_pool.bosh_lab.name
            volume = libvirt_volume.mgmt_root.name
          }
        }
      },
      {
        device = "cdrom"
        target = {
          dev = "sda"
          bus = "sata"
        }
        source = {
          file = {
            file = libvirt_cloudinit_disk.mgmt_init.path
          }
        }
      }
    ]

    consoles = [{
      target = {
        type = "serial"
        port = 0
      }
    }]

    graphics = [{
      vnc = {
        listen    = "127.0.0.1"
        auto_port = true
      }
    }]

    # Share state directory with VM via 9p filesystem
    filesystems = [{
      access_mode = "mapped"
      read_only   = false
      source = {
        mount = {
          dir = var.state_dir
        }
      }
      target = {
        dir = "state"
      }
    }]
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
