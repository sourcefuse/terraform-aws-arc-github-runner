# terraform-refarch-github-runner

## Overview

SourceFuse AWS Reference Architecture (ARC) Terraform module for managing GitHub Runner. 

## Usage
:warning: At this time, this module only supports **Debian** / **Ubuntu** AMIs. 
When choosing an AMI, please be sure to select either **Ubuntu** or **Debian**. :warning:  

To see a full example, check out the [main.tf](./example/main.tf) file in the example folder.  

```hcl
module "runner" {
  source = "git::https://github.com/sourcefuse/terraform-refarch-github-runner"
}
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.3, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 4.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | 3.2.1 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 4.50.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.1 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.4.3 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_runner"></a> [runner](#module\_runner) | git::https://github.com/cloudposse/terraform-aws-ec2-instance | 0.45.2 |
| <a name="module_ssh_key_pair"></a> [ssh\_key\_pair](#module\_ssh\_key\_pair) | git::https://github.com/cloudposse/terraform-aws-key-pair | 0.18.3 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_policy.runner_bucket_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.runner_bucket_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_s3_bucket.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_acl.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl) | resource |
| [aws_s3_bucket_versioning.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_object.docker_compose](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_ssm_association.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_association.scheduled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association) | resource |
| [aws_ssm_document.docker_compose](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [aws_ssm_document.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |
| [null_resource.cleanup](https://registry.terraform.io/providers/hashicorp/null/3.2.1/docs/resources/resource) | resource |
| [random_string.runner](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami"></a> [ami](#input\_ami) | AMI information for the EC2 instance | <pre>object({<br>    id       = string<br>    owner_id = string<br>  })</pre> | <pre>{<br>  "id": "ami-04505e74c0741db8d",<br>  "owner_id": "099720109477"<br>}</pre> | no |
| <a name="input_associate_public_ip_address"></a> [associate\_public\_ip\_address](#input\_associate\_public\_ip\_address) | Associate a public IP address with the instance | `bool` | `false` | no |
| <a name="input_ec2_runner_iam_role_policy_arns"></a> [ec2\_runner\_iam\_role\_policy\_arns](#input\_ec2\_runner\_iam\_role\_policy\_arns) | IAM role policies to attach to the Runner instance | `list(string)` | <pre>[<br>  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",<br>  "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"<br>]</pre> | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of the environment, i.e. dev, stage, prod | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | The instance type for the EC2 instance. Default is t3a.medium. | `string` | `"t3a.medium"` | no |
| <a name="input_monitoring_enabled"></a> [monitoring\_enabled](#input\_monitoring\_enabled) | Launched EC2 instance will have detailed monitoring enabled | `bool` | `true` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of the project, i.e. refarch | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | n/a | yes |
| <a name="input_root_block_device_encrypted"></a> [root\_block\_device\_encrypted](#input\_root\_block\_device\_encrypted) | Whether to encrypt the root block device | `bool` | `true` | no |
| <a name="input_root_block_device_kms_key_id"></a> [root\_block\_device\_kms\_key\_id](#input\_root\_block\_device\_kms\_key\_id) | KMS key ID used to encrypt EBS volume. When specifying root\_block\_device\_kms\_key\_id, root\_block\_device\_encrypted needs to be set to true | `string` | `null` | no |
| <a name="input_root_volume_size"></a> [root\_volume\_size](#input\_root\_volume\_size) | Size of the root volume in gigabytes | `string` | `"80"` | no |
| <a name="input_root_volume_type"></a> [root\_volume\_type](#input\_root\_volume\_type) | Type of root volume. Can be standard, gp2, gp3, io1 or io2 | `string` | `"gp2"` | no |
| <a name="input_runner_labels"></a> [runner\_labels](#input\_runner\_labels) | Labels to assign the GitHub Runner. If no values are given, the default labels will be:<br>  - `self-hosted`<br>  - Base OS, i.e. `Linux`<br>  - Architecture, i.e. `X64`<br>These labels cannot be overridden.<br>Separate labels via comma, i.e. `dev,docker,another_label` | `string` | `""` | no |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | Name to assign the GitHub Runner. If no value is given, it will use the ec2 instance name. | `string` | `null` | no |
| <a name="input_runner_organization"></a> [runner\_organization](#input\_runner\_organization) | GitHub Organization the runner belongs to. | `string` | `"sourcefuse"` | no |
| <a name="input_runner_token"></a> [runner\_token](#input\_runner\_token) | GitHub Runner token used for registering the runner to the Organization. | `string` | n/a | yes |
| <a name="input_security_group_rules"></a> [security\_group\_rules](#input\_security\_group\_rules) | Security group rules for the EC2 instance running the GitHub Runner | <pre>list(object({<br>    type        = string<br>    from_port   = number<br>    to_port     = number<br>    protocol    = string<br>    cidr_blocks = list(string)<br>  }))</pre> | <pre>[<br>  {<br>    "cidr_blocks": [<br>      "0.0.0.0/0"<br>    ],<br>    "from_port": 0,<br>    "protocol": "-1",<br>    "to_port": 65535,<br>    "type": "egress"<br>  }<br>]</pre> | no |
| <a name="input_ssm_patch_manager_enabled"></a> [ssm\_patch\_manager\_enabled](#input\_ssm\_patch\_manager\_enabled) | Whether to enable SSM Patch manager | `bool` | `true` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Subnet ID for the EC2 instance to be assigned to | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Default tags to apply to every resource | `map(string)` | `{}` | no |
| <a name="input_volume_tags_enabled"></a> [volume\_tags\_enabled](#input\_volume\_tags\_enabled) | Whether or not to copy instance tags to root and EBS volumes | `bool` | `true` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for EC2 instance to reside in | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ec2_runner_instance_id"></a> [ec2\_runner\_instance\_id](#output\_ec2\_runner\_instance\_id) | Instance ID of the EC2 Runner |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->

## Development

### Prerequisites

- [terraform](https://learn.hashicorp.com/terraform/getting-started/install#installing-terraform)
- [terraform-docs](https://github.com/segmentio/terraform-docs)
- [pre-commit](https://pre-commit.com/#install)
- [golang](https://golang.org/doc/install#install)
- [golint](https://github.com/golang/lint#installation)

### Configurations

- Configure pre-commit hooks
  ```sh
  pre-commit install
  ```

### Tests
- Tests are available in `test` directory
- Configure the dependencies
  ```sh
  cd test
  go mod init github.com/sourcefuse/terraform-aws-ref-arch-db
  go get github.com/gruntwork-io/terratest/modules/terraform
  ```
- Now execute the test  
  ```sh
  cd test/
  go test
  ```

## Authors

This project is authored by:
- SourceFuse
