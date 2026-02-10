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
  autostart = true

  forward = {
    mode = "nat"
  }

  dns = {
    enable = "yes"
  }

  # No DHCP — BOSH manages IP assignment via CPI
  ips = [{
    address = var.network_gateway
    prefix  = tonumber(split("/", var.network_cidr)[1])
  }]
}

output "network_id" {
  value = libvirt_network.bosh_lab.id
}

output "network_name" {
  value = libvirt_network.bosh_lab.name
}
