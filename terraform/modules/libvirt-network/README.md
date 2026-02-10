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
| [libvirt_network.bosh_lab](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs/resources/network) | resource |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | n/a | `string` | n/a | yes |
| <a name="input_network_gateway"></a> [network\_gateway](#input\_network\_gateway) | n/a | `string` | n/a | yes |
| <a name="input_network_name"></a> [network\_name](#input\_network\_name) | n/a | `string` | n/a | yes |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | n/a |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | n/a |
<!-- END_TF_DOCS -->