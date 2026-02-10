variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "network_name" {
  description = "Name of the libvirt network for the BOSH lab"
  type        = string
  default     = "bosh-lab"
}

variable "network_cidr" {
  description = "CIDR for the BOSH lab network"
  type        = string
  default     = "10.245.0.0/24"
}

variable "network_gateway" {
  description = "Gateway IP for the BOSH lab network"
  type        = string
  default     = "10.245.0.1"
}

variable "mgmt_vm_name" {
  description = "Name of the management VM"
  type        = string
  default     = "bosh-lab-mgmt"
}

variable "mgmt_vm_vcpu" {
  description = "Number of vCPUs for the management VM"
  type        = number
  default     = 4
}

variable "mgmt_vm_memory_mb" {
  description = "Memory in MB for the management VM"
  type        = number
  default     = 8192
}

variable "mgmt_vm_disk_gb" {
  description = "Root disk size in GB for the management VM"
  type        = number
  default     = 80
}

variable "mgmt_vm_ip" {
  description = "Static IP for the management VM"
  type        = string
  default     = "10.245.0.2"
}

variable "cloud_image_path" {
  description = "Path to the Ubuntu 22.04 cloud image (qcow2)"
  type        = string
}

variable "cloud_init_path" {
  description = "Path to the cloud-init user-data file"
  type        = string
}

variable "state_dir" {
  description = "Path to the host state directory to share with the VM"
  type        = string
}

variable "pool_path" {
  description = "Path for the libvirt storage pool"
  type        = string
  default     = "/var/lib/libvirt/images/bosh-lab"
}
