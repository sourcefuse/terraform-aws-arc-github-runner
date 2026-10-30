# EKS GitHub Actions runner example

Deploys two runner scale sets onto an existing EKS cluster by calling the **root module** (`source = "../../"`)
with `eks_runner_config.create = true` and `create_ec2_runner = false`. The root module uses the [`eks-runner`](../../modules/eks-runner) submodule
internally:

| Scale set | Mode | Purpose |
|-----------|------|---------|
| `<namespace>-<environment>-github-runner` | `dind` | General jobs, including `docker build`. |
| `<namespace>-<environment>-github-runner-k8s` | `kubernetes` | Unprivileged job containers, with read-only ECR access through the pod's IAM role. |

It also installs the EBS CSI driver add-on and an encrypted gp3 StorageClass for the `kubernetes` mode work volume.

## Prerequisites

- An existing EKS cluster with worker nodes (managed node group, Karpenter or EKS Auto Mode).
- Your AWS identity has an EKS access entry on the cluster.
- For `iam_auth_type = "pod_identity"`: the `eks-pod-identity-agent` add-on. For `"irsa"`: the cluster IAM OIDC provider.
- A GitHub PAT stored as an SSM SecureString at `github_token_ssm_path`. Use a fine-grained token with
  **Administration: read & write** on the target repository, or org self-hosted runner permissions.
- On EKS Auto Mode, set `install_ebs_csi_driver = false` and use the `ebs.csi.eks.amazonaws.com` provisioner.

## Usage

```shell
terraform init
terraform apply \
  -var 'cluster_name=my-eks-cluster' \
  -var 'github_config_url=https://github.com/my-org/my-repo'
```

Use the scale set names from the `runner_scale_sets` output in your workflows:

```yaml
jobs:
  build:
    runs-on: arc-dev-github-runner
    steps:
      - run: echo "Hello from EKS"

  test:
    runs-on: arc-dev-github-runner-k8s
    container: node:22 # required in kubernetes mode
    steps:
      - run: node --version
```

## Cleanup

```shell
terraform destroy
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40, < 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.12, < 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.20, < 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_github_runner"></a> [github\_runner](#module\_github\_runner) | ../../ | n/a |
| <a name="module_tags"></a> [tags](#module\_tags) | sourcefuse/arc-tags/aws | 1.2.5 |

## Resources

| Name | Type |
|------|------|
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster) | data source |
| [aws_iam_openid_connect_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_openid_connect_provider) | data source |
| [aws_ssm_parameter.github_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the existing EKS cluster to deploy the runners onto. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of the environment, i.e. dev, stage, prod | `string` | `"dev"` | no |
| <a name="input_github_config_url"></a> [github\_config\_url](#input\_github\_config\_url) | GitHub URL the runners register against. Organization URL<br/>(https://github.com/my-org), repository URL<br/>(https://github.com/my-org/my-repo), or enterprise URL<br/>(https://github.com/enterprises/my-enterprise). | `string` | n/a | yes |
| <a name="input_github_token_ssm_path"></a> [github\_token\_ssm\_path](#input\_github\_token\_ssm\_path) | SSM Parameter Store path (SecureString) holding the GitHub PAT used to register runners. | `string` | `"/arc/dev/github/token"` | no |
| <a name="input_iam_auth_type"></a> [iam\_auth\_type](#input\_iam\_auth\_type) | How pods get IAM roles: "pod\_identity" (needs the eks-pod-identity-agent add-on) or "irsa" (needs the cluster OIDC provider). | `string` | `"pod_identity"` | no |
| <a name="input_install_ebs_csi_driver"></a> [install\_ebs\_csi\_driver](#input\_install\_ebs\_csi\_driver) | Install the EBS CSI driver add-on. Set to false on EKS Auto Mode or if the driver is already installed. | `bool` | `true` | no |
| <a name="input_max_runners"></a> [max\_runners](#input\_max\_runners) | Maximum number of runners per scale set. | `number` | `3` | no |
| <a name="input_min_runners"></a> [min\_runners](#input\_min\_runners) | Minimum number of idle runners kept warm in the default scale set. | `number` | `0` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of the project, i.e. arc | `string` | `"arc"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_controller_namespace"></a> [controller\_namespace](#output\_controller\_namespace) | Kubernetes namespace the controller is deployed in. |
| <a name="output_runner_namespace"></a> [runner\_namespace](#output\_runner\_namespace) | Kubernetes namespace the runner scale sets are deployed in. |
| <a name="output_runner_scale_sets"></a> [runner\_scale\_sets](#output\_runner\_scale\_sets) | Deployed runner scale sets. Use `name` in a workflow's `runs-on:`. |
| <a name="output_storage_class_name"></a> [storage\_class\_name](#output\_storage\_class\_name) | StorageClass used for runner work volumes. |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
