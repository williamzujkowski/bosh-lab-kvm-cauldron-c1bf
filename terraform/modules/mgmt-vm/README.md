<!-- BEGIN_TF_DOCS -->


### Requirements

No requirements.

### Providers

| Name | Version |
|------|---------|
| <a name="provider_libvirt"></a> [libvirt](#provider\_libvirt) | n/a |

### Resources

| Name | Type |
|------|------|
| [libvirt_cloudinit_disk.mgmt_init](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/cloudinit_disk) | resource |
| [libvirt_domain.mgmt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/domain) | resource |
| [libvirt_pool.bosh_lab](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/pool) | resource |
| [libvirt_volume.mgmt_root](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/volume) | resource |
| [libvirt_volume.ubuntu_base](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/volume) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud_image_path"></a> [cloud\_image\_path](#input\_cloud\_image\_path) | n/a | `string` | n/a | yes |
| <a name="input_cloud_init_path"></a> [cloud\_init\_path](#input\_cloud\_init\_path) | n/a | `string` | n/a | yes |
| <a name="input_disk_gb"></a> [disk\_gb](#input\_disk\_gb) | n/a | `number` | n/a | yes |
| <a name="input_memory_mb"></a> [memory\_mb](#input\_memory\_mb) | n/a | `number` | n/a | yes |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | n/a | `string` | n/a | yes |
| <a name="input_pool_path"></a> [pool\_path](#input\_pool\_path) | n/a | `string` | n/a | yes |
| <a name="input_state_dir"></a> [state\_dir](#input\_state\_dir) | n/a | `string` | n/a | yes |
| <a name="input_static_ip"></a> [static\_ip](#input\_static\_ip) | n/a | `string` | n/a | yes |
| <a name="input_vcpu"></a> [vcpu](#input\_vcpu) | n/a | `number` | n/a | yes |
| <a name="input_vm_name"></a> [vm\_name](#input\_vm\_name) | n/a | `string` | n/a | yes |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_vm_id"></a> [vm\_id](#output\_vm\_id) | n/a |
| <a name="output_vm_ip"></a> [vm\_ip](#output\_vm\_ip) | n/a |
<!-- END_TF_DOCS -->