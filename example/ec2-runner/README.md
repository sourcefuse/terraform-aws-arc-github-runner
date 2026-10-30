# terraform-refarch-github-runner Example

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40, < 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_runner"></a> [runner](#module\_runner) | ../../ | n/a |
| <a name="module_tags"></a> [tags](#module\_tags) | sourcefuse/arc-tags/aws | 1.2.5 |

## Resources

| Name | Type |
|------|------|
| [aws_ami.ubuntu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_ssm_parameter.github_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_subnets.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | Name of the environment, i.e. dev, stage, prod | `string` | `"dev"` | no |
| <a name="input_github_token_ssm_path"></a> [github\_token\_ssm\_path](#input\_github\_token\_ssm\_path) | SSM SecureString path holding the GitHub PAT. Keep this separate from the root module's /github-runner/token registration parameter. | `string` | `"/arc/poc/github-runner/token"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of the project, i.e. arc | `string` | `"arc"` | no |
| <a name="input_private_subnet_names"></a> [private\_subnet\_names](#input\_private\_subnet\_names) | Private subnet names to add the runner | `list(string)` | <pre>[<br/>  "arc-poc-private-subnet-private-us-east-1a",<br/>  "arc-poc-private-subnet-private-us-east-1b"<br/>]</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | `"us-east-1"` | no |
| <a name="input_vpc_names"></a> [vpc\_names](#input\_vpc\_names) | Private subnet names to add the runner | `list(string)` | <pre>[<br/>  "arc-poc-vpc"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ec2_runner_instance_id"></a> [ec2\_runner\_instance\_id](#output\_ec2\_runner\_instance\_id) | Instance ID of the EC2 Runner |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
