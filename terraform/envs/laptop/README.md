<!-- BEGIN_TF_DOCS -->


### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.13.0 |
| <a name="requirement_libvirt"></a> [libvirt](#requirement\_libvirt) | ~> 0.9.2 |

### Providers

No providers.

### Resources

No resources.

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_image_path"></a> [cloud\_image\_path](#input\_cloud\_image\_path) | Path to the Ubuntu 22.04 cloud image (qcow2) | `string` | n/a | yes |
| <a name="input_cloud_init_path"></a> [cloud\_init\_path](#input\_cloud\_init\_path) | Path to the cloud-init user-data file | `string` | n/a | yes |
| <a name="input_state_dir"></a> [state\_dir](#input\_state\_dir) | Path to the host state directory to share with the VM | `string` | n/a | yes |
| <a name="input_libvirt_uri"></a> [libvirt\_uri](#input\_libvirt\_uri) | Libvirt connection URI | `string` | `"qemu:///system"` | no |
| <a name="input_mgmt_vm_disk_gb"></a> [mgmt\_vm\_disk\_gb](#input\_mgmt\_vm\_disk\_gb) | Root disk size in GB for the management VM | `number` | `80` | no |
| <a name="input_mgmt_vm_ip"></a> [mgmt\_vm\_ip](#input\_mgmt\_vm\_ip) | Static IP for the management VM | `string` | `"10.245.0.2"` | no |
| <a name="input_mgmt_vm_memory_mb"></a> [mgmt\_vm\_memory\_mb](#input\_mgmt\_vm\_memory\_mb) | Memory in MB for the management VM | `number` | `8192` | no |
| <a name="input_mgmt_vm_name"></a> [mgmt\_vm\_name](#input\_mgmt\_vm\_name) | Name of the management VM | `string` | `"bosh-lab-mgmt"` | no |
| <a name="input_mgmt_vm_vcpu"></a> [mgmt\_vm\_vcpu](#input\_mgmt\_vm\_vcpu) | Number of vCPUs for the management VM | `number` | `4` | no |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | CIDR for the BOSH lab network | `string` | `"10.245.0.0/24"` | no |
| <a name="input_network_gateway"></a> [network\_gateway](#input\_network\_gateway) | Gateway IP for the BOSH lab network | `string` | `"10.245.0.1"` | no |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | Name of the libvirt network for the BOSH lab | `string` | `"bosh-lab"` | no |
| <a name="input_pool_path"></a> [pool\_path](#input\_pool\_path) | Path for the libvirt storage pool | `string` | `"/var/lib/libvirt/images/bosh-lab"` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_mgmt_vm_ip"></a> [mgmt\_vm\_ip](#output\_mgmt\_vm\_ip) | IP address of the management VM |
| <a name="output_mgmt_vm_name"></a> [mgmt\_vm\_name](#output\_mgmt\_vm\_name) | Name of the management VM |
| <a name="output_network_cidr"></a> [network\_cidr](#output\_network\_cidr) | CIDR of the BOSH lab network |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Name of the BOSH lab libvirt network |
<!-- END_TF_DOCS -->