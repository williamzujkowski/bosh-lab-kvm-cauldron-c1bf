output "network_name" {
  description = "Name of the BOSH lab libvirt network"
  value       = module.network.network_name
}

output "network_cidr" {
  description = "CIDR of the BOSH lab network"
  value       = var.network_cidr
}

output "mgmt_vm_ip" {
  description = "IP address of the management VM"
  value       = var.mgmt_vm_ip
}

output "mgmt_vm_name" {
  description = "Name of the management VM"
  value       = var.mgmt_vm_name
}
