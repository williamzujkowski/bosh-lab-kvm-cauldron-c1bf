module "network" {
  source = "./modules/libvirt-network"

  network_name    = var.network_name
  network_cidr    = var.network_cidr
  network_gateway = var.network_gateway
}

module "mgmt_vm" {
  source = "./modules/mgmt-vm"

  vm_name         = var.mgmt_vm_name
  vcpu            = var.mgmt_vm_vcpu
  memory_mb       = var.mgmt_vm_memory_mb
  disk_gb         = var.mgmt_vm_disk_gb
  static_ip       = var.mgmt_vm_ip
  network_id      = module.network.network_id
  cloud_image_path = var.cloud_image_path
  cloud_init_path  = var.cloud_init_path
  state_dir       = var.state_dir
  pool_path       = var.pool_path

  depends_on = [module.network]
}
