variable "network_name" {
  type = string
}

variable "network_cidr" {
  type = string
}

variable "network_gateway" {
  type = string
}

resource "libvirt_network" "bosh_lab" {
  name      = var.network_name
  mode      = "nat"
  autostart = true

  addresses = [var.network_cidr]

  dns {
    enabled = true
  }

  # Do NOT provide DHCP — BOSH manages IP assignment via CPI
  dhcp {
    enabled = false
  }
}

output "network_id" {
  value = libvirt_network.bosh_lab.id
}

output "network_name" {
  value = libvirt_network.bosh_lab.name
}
