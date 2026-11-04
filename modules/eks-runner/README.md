# eks-runner

Self-hosted GitHub Actions runners on **Amazon EKS**, using the official
[Actions Runner Controller](https://github.com/actions/actions-runner-controller)
(ARC) runner scale set charts. This is the Kubernetes-native alternative to the
root module, which provisions an EC2/SSM-based runner.

## Features

- Official `gha-runner-scale-set-controller` + `gha-runner-scale-set` charts, pinned and version-validated.
- **Multiple runner scale sets** from one module call, each with its own min/max runners, container mode,
  image, resources, scheduling and AWS permissions.
- **Least-privilege AWS access for runner pods** via EKS Pod Identity (default) or IRSA. Trust
  policies are scoped to the exact namespace and service account of each scale set.
- **GitHub App (recommended) or PAT** auth, or bring your own secret (e.g. External Secrets Operator)
  so credentials never enter Terraform state.
- Optional **EBS CSI driver** add-on with its own scoped IAM role, and an **encrypted** EBS
  StorageClass (optional customer managed KMS key) for `kubernetes` mode work volumes.
- Safe Helm rollouts: `atomic`, `wait`, `cleanup_on_fail`, bounded `max_history`.
- Input validation for names, URLs, ARNs, container modes and `min_runners <= max_runners`.

## Architecture

```
arc-systems namespace                 arc-runners namespace
┌────────────────────────┐            ┌────────────────────────────────────────┐
│ gha-rs-controller      │──manages──▶│ scale set "default" (dind)             │
│ listener per scale set │            │ scale set "k8s"     (kubernetes mode)  │
└────────────────────────┘            │   └─ runner pods ── IAM role (optional)│
          ▲  long-poll                │ Secret: github config (App / PAT)      │
          │                           └────────────────────────────────────────┘
     GitHub Actions
```

Runner pods are ephemeral: one pod per job, scaled between `min_runners` and `max_runners`.

## Usage

The usual entry point is the root module with `eks_runner_config.create = true`. Every input below is exposed there through
`eks_runner_config`:

```hcl
module "github_runner" {
  source = "sourcefuse/arc-github-runner/aws"
  # version = "x.y.z"

  namespace              = "arc"
  environment            = "dev"
  region                 = "us-east-1"
  create_ec2_runner      = false
  github_app_private_key = var.github_app_private_key

  eks_runner_config = {
    create                     = true
    cluster_name               = "my-eks-cluster"
    github_config_url          = "https://github.com/my-org"
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id

    runner_scale_sets = {
      default = { min_runners = 1, max_runners = 10 }
    }
  }
}
```

The submodule can also be called directly:
```hcl
module "eks_runner" {
  source = "sourcefuse/arc-github-runner/aws//modules/eks-runner"
  # version = "x.y.z"

  namespace    = "arc"
  environment  = "dev"
  cluster_name = "my-eks-cluster"

  github_config_url          = "https://github.com/my-org"
  github_auth_method         = "github_app"
  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key

  runner_scale_sets = {
    default = {
      min_runners = 1
      max_runners = 10
      resources   = { requests = { cpu = "1", memory = "2Gi" } }
    }

    deploy = {
      container_mode = "kubernetes"
      max_runners    = 5
      iam_policy_arns = {
        ecr_push = aws_iam_policy.ecr_push.arn
      }
    }
  }

  tags = module.tags.tags
}
```

Target a scale set from a workflow by its name (see the `runner_scale_sets` output):

```yaml
jobs:
  build:
    runs-on: arc-dev-github-runner-default
```

A complete, runnable example is in [`example/eks-runner`](../../example/eks-runner).

### Provider configuration

The module does **not** configure providers, so it stays cluster-agnostic. Configure `aws`,
`helm` and `kubernetes` in the calling root module. Prefer `exec` authentication so the EKS token
is refreshed during long applies:

```hcl
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "my-eks-cluster"]
    }
  }
}
```

## Security considerations

- **Credentials**: prefer a **GitHub App** over a PAT (scoped permissions, short-lived tokens, not tied
  to a user). Credentials passed as inputs are stored in Terraform state. Use an encrypted remote
  backend, or set `existing_github_config_secret_name` and manage the secret outside Terraform.
- **Container modes**: `dind` runs a **privileged** Docker sidecar. Use it only for trusted
  workloads. `kubernetes` mode runs job containers as separate, unprivileged pods.
- **Public repositories**: do not attach self-hosted runners to public repositories. Forked pull
  requests can run arbitrary code on them.
- **AWS permissions**: grant each scale set only the policies its jobs need. Each scale set gets its own
  role, trusted only by its own service account. Use `iam_role_permissions_boundary` where required.
- **Images**: pin `runner_image` to a version or digest in production rather than `latest`.

## Container modes

| `container_mode`      | Behavior |
|-----------------------|----------|
| `dind` (default)      | Docker-in-Docker sidecar (privileged). Jobs can `docker build` / `docker run`. |
| `kubernetes`          | Job containers and services run as separate pods. Needs a work volume; jobs must set `container:`. |
| `kubernetes-novolume` | Kubernetes mode without a persistent work volume. |
| `""`                  | No managed mode; configure the pod template yourself via `values`. |

## IAM for runner pods

Set `iam_policy_arns` (static keys => policy ARNs) and/or `iam_policy_json` on a scale set to create a role
for its runner pods.

| `iam_auth_type`          | Requirement | How it is wired |
|--------------------------|-------------|-----------------|
| `pod_identity` (default) | `eks-pod-identity-agent` add-on (built in on EKS Auto Mode) | `aws_eks_pod_identity_association` |
| `irsa`                   | Cluster IAM OIDC provider (`oidc_provider_arn`) | `eks.amazonaws.com/role-arn` annotation on the chart's runner service account |

If you override `template.spec.serviceAccountName` via `values`, the module-created role will not match the
service account. Manage IAM yourself in that case.

## Storage

Only needed for the `kubernetes` container mode (or jobs mounting PVCs).

- `install_ebs_csi_driver = true` installs the `aws-ebs-csi-driver` add-on with a scoped IAM role (Pod Identity
  or IRSA, following `iam_auth_type`). Not needed on EKS Auto Mode.
- `create_storage_class = true` creates an encrypted EBS StorageClass. Use
  `storage_class_provisioner = "ebs.csi.eks.amazonaws.com"` on EKS Auto Mode.
- A scale set's work volume uses `work_volume_storage_class`, else the class created here, else the cluster default.

## Upgrading the charts

Controller and scale set charts must use the same `chart_version`. Helm does not upgrade CRDs. When changing
minor versions, follow the
[ARC upgrade guide](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/deploying-runner-scale-sets-with-actions-runner-controller#upgrading-arc):
uninstall the scale sets and controller, update the CRDs, then apply again.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40, < 7.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.12, < 4.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.20, < 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.71.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 3.3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eks_addon.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_pod_identity_association.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ebs_csi_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.runner](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.scale_set](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_namespace_v1.controller](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_namespace_v1.runners](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.github_config](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_storage_class_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.ebs_csi_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ebs_csi_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runner_irsa_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runner_pod_identity_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_chart_oci_registry"></a> [chart\_oci\_registry](#input\_chart\_oci\_registry) | OCI registry base path hosting the official Actions Runner Controller Helm charts. | `string` | `"oci://ghcr.io/actions/actions-runner-controller-charts"` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Version of both ARC charts (controller and scale set must match). Minimum<br/>supported: 0.13.0. Helm does not upgrade CRDs, so follow the ARC upgrade<br/>guide when changing minor versions. | `string` | `"0.15.1"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster the runners are deployed onto. Used for EKS Pod Identity associations and EKS add-ons. | `string` | n/a | yes |
| <a name="input_controller_namespace"></a> [controller\_namespace](#input\_controller\_namespace) | Kubernetes namespace where the gha-runner-scale-set-controller is deployed. | `string` | `"arc-systems"` | no |
| <a name="input_controller_release_name"></a> [controller\_release\_name](#input\_controller\_release\_name) | Helm release name of the controller. | `string` | `"arc"` | no |
| <a name="input_controller_service_account"></a> [controller\_service\_account](#input\_controller\_service\_account) | Service account of an externally managed controller (install\_controller =<br/>false). If null, the chart discovers it at install time. | <pre>object({<br/>    name      = string<br/>    namespace = string<br/>  })</pre> | `null` | no |
| <a name="input_controller_values"></a> [controller\_values](#input\_controller\_values) | Additional raw YAML values documents merged into the controller release (later documents win). | `list(string)` | `[]` | no |
| <a name="input_create_controller_namespace"></a> [create\_controller\_namespace](#input\_create\_controller\_namespace) | Whether this module creates the controller namespace (only used when install\_controller is true). | `bool` | `true` | no |
| <a name="input_create_k8s_namespace"></a> [create\_k8s\_namespace](#input\_create\_k8s\_namespace) | Whether this module creates the runner namespace. Set to false if it already exists. | `bool` | `true` | no |
| <a name="input_create_storage_class"></a> [create\_storage\_class](#input\_create\_storage\_class) | Whether to create an encrypted EBS StorageClass for runner work volumes. | `bool` | `false` | no |
| <a name="input_ebs_csi_addon_version"></a> [ebs\_csi\_addon\_version](#input\_ebs\_csi\_addon\_version) | Version of the aws-ebs-csi-driver add-on. If null, the cluster's default version is used. | `string` | `null` | no |
| <a name="input_ebs_csi_kms_key_arn"></a> [ebs\_csi\_kms\_key\_arn](#input\_ebs\_csi\_kms\_key\_arn) | Customer managed KMS key the EBS CSI driver may use for volume encryption. If null, the AWS managed key is used. | `string` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of the environment, i.e. dev, stage, prod | `string` | n/a | yes |
| <a name="input_existing_github_config_secret_name"></a> [existing\_github\_config\_secret\_name](#input\_existing\_github\_config\_secret\_name) | Name of an existing Kubernetes secret (in k8s\_namespace) holding GitHub<br/>credentials, e.g. synced by External Secrets Operator. When set, the module<br/>does not create a secret and the credential inputs below are ignored. This<br/>keeps credentials out of Terraform state. | `string` | `null` | no |
| <a name="input_github_app_id"></a> [github\_app\_id](#input\_github\_app\_id) | GitHub App ID or client ID (github\_auth\_method = "github\_app"). | `string` | `null` | no |
| <a name="input_github_app_installation_id"></a> [github\_app\_installation\_id](#input\_github\_app\_installation\_id) | GitHub App installation ID (github\_auth\_method = "github\_app"). | `string` | `null` | no |
| <a name="input_github_app_private_key"></a> [github\_app\_private\_key](#input\_github\_app\_private\_key) | GitHub App private key in PEM format (github\_auth\_method = "github\_app"). | `string` | `null` | no |
| <a name="input_github_auth_method"></a> [github\_auth\_method](#input\_github\_auth\_method) | GitHub authentication method: "github\_app" (recommended) or "pat". | `string` | `"github_app"` | no |
| <a name="input_github_config_url"></a> [github\_config\_url](#input\_github\_config\_url) | Default GitHub URL runners register against: an organization<br/>(https://github.com/my-org), repository (https://github.com/my-org/my-repo)<br/>or enterprise (https://github.com/enterprises/my-enterprise). Can be<br/>overridden per scale set. | `string` | n/a | yes |
| <a name="input_github_token"></a> [github\_token](#input\_github\_token) | GitHub Personal Access Token (github\_auth\_method = "pat"). Prefer a fine-grained token scoped to the target org/repo. | `string` | `null` | no |
| <a name="input_helm_max_history"></a> [helm\_max\_history](#input\_helm\_max\_history) | Maximum number of Helm release revisions kept per release. | `number` | `10` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Seconds to wait for each Helm release to become ready. | `number` | `600` | no |
| <a name="input_iam_auth_type"></a> [iam\_auth\_type](#input\_iam\_auth\_type) | How pods get IAM roles: "pod\_identity" (EKS Pod Identity, recommended;<br/>requires the eks-pod-identity-agent add-on, built in on EKS Auto Mode) or<br/>"irsa" (IAM Roles for Service Accounts; requires oidc\_provider\_arn). | `string` | `"pod_identity"` | no |
| <a name="input_iam_role_path"></a> [iam\_role\_path](#input\_iam\_role\_path) | Path for IAM roles created by this module. | `string` | `"/"` | no |
| <a name="input_iam_role_permissions_boundary"></a> [iam\_role\_permissions\_boundary](#input\_iam\_role\_permissions\_boundary) | ARN of a permissions boundary applied to IAM roles created by this module. | `string` | `null` | no |
| <a name="input_install_controller"></a> [install\_controller](#input\_install\_controller) | Whether to install the gha-runner-scale-set-controller. Install exactly one<br/>controller per cluster; set to false when it is managed elsewhere and set<br/>`controller_service_account` instead. | `bool` | `true` | no |
| <a name="input_install_ebs_csi_driver"></a> [install\_ebs\_csi\_driver](#input\_install\_ebs\_csi\_driver) | Install the aws-ebs-csi-driver EKS add-on with an IAM role. Needed for<br/>persistent work volumes ("kubernetes" mode) on clusters without EKS Auto<br/>Mode. Leave false on Auto Mode or if the driver is already installed. | `bool` | `false` | no |
| <a name="input_k8s_namespace"></a> [k8s\_namespace](#input\_k8s\_namespace) | Kubernetes namespace where the runner scale sets (and their pods) are deployed. | `string` | `"arc-runners"` | no |
| <a name="input_k8s_namespace_labels"></a> [k8s\_namespace\_labels](#input\_k8s\_namespace\_labels) | Labels applied to the namespaces created by this module, e.g. Pod Security<br/>Admission labels. Note: "dind" container mode needs privileged pods. | `map(string)` | `{}` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix used to name resources (Kubernetes secret, IAM roles, default scale<br/>set names). If null, defaults to `<namespace>-<environment>-github-runner`. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of the project, i.e. refarch | `string` | n/a | yes |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the cluster's IAM OIDC provider. Required only when `iam_auth_type`<br/>is "irsa" and an IAM role is created (runner IAM policies or the EBS CSI<br/>driver). | `string` | `null` | no |
| <a name="input_runner_scale_sets"></a> [runner\_scale\_sets](#input\_runner\_scale\_sets) | Runner scale sets to deploy, keyed by a short identifier. Each scale set is a<br/>separate Helm release and autoscaling pool. Workflows target a scale set with<br/>`runs-on: <name>`.<br/><br/>- name: scale set name (used in `runs-on:`). Defaults to `<name_prefix>-<key>`. Max 53 chars (Helm release name limit).<br/>- github\_config\_url: overrides the module-level github\_config\_url.<br/>- runner\_group: GitHub runner group (must already exist for org/enterprise scopes).<br/>- min\_runners / max\_runners: idle runners kept warm / upper scaling bound.<br/>- container\_mode: "dind", "kubernetes", "kubernetes-novolume" or "" (configure via values).<br/>- runner\_image: runner container image. Pin a version or digest in production.<br/>- resources: runner container requests/limits, e.g. { requests = { cpu = "500m", memory = "1Gi" } }.<br/>- node\_selector / tolerations: runner pod scheduling.<br/>- work\_volume\_storage\_class / work\_volume\_size: work volume for "kubernetes" mode.<br/>  Storage class defaults to the class created by this module, else the cluster default.<br/>- iam\_policy\_arns: map of static name => IAM policy ARN granted to runner pods.<br/>- iam\_policy\_json: inline IAM policy document granted to runner pods.<br/>- values: extra raw YAML values documents for this release (later documents win). | <pre>map(object({<br/>    name              = optional(string)<br/>    github_config_url = optional(string)<br/>    runner_group      = optional(string, "default")<br/>    min_runners       = optional(number, 0)<br/>    max_runners       = optional(number, 5)<br/>    container_mode    = optional(string, "dind")<br/><br/>    runner_image = optional(string, "ghcr.io/actions/actions-runner:latest")<br/>    resources = optional(object({<br/>      requests = optional(map(string), {})<br/>      limits   = optional(map(string), {})<br/>    }), {})<br/>    node_selector = optional(map(string), {})<br/>    tolerations = optional(list(object({<br/>      key                = optional(string)<br/>      operator           = optional(string)<br/>      value              = optional(string)<br/>      effect             = optional(string)<br/>      toleration_seconds = optional(number)<br/>    })), [])<br/><br/>    work_volume_storage_class = optional(string)<br/>    work_volume_size          = optional(string, "10Gi")<br/><br/>    iam_policy_arns = optional(map(string), {})<br/>    iam_policy_json = optional(string)<br/><br/>    values = optional(list(string), [])<br/>  }))</pre> | <pre>{<br/>  "default": {}<br/>}</pre> | no |
| <a name="input_storage_class_is_default"></a> [storage\_class\_is\_default](#input\_storage\_class\_is\_default) | Whether the created StorageClass is marked as the cluster default. | `bool` | `false` | no |
| <a name="input_storage_class_name"></a> [storage\_class\_name](#input\_storage\_class\_name) | Name of the StorageClass created when create\_storage\_class is true. | `string` | `"arc-runner-gp3"` | no |
| <a name="input_storage_class_provisioner"></a> [storage\_class\_provisioner](#input\_storage\_class\_provisioner) | CSI provisioner: "ebs.csi.aws.com" (EBS CSI add-on) or "ebs.csi.eks.amazonaws.com" (EKS Auto Mode). | `string` | `"ebs.csi.aws.com"` | no |
| <a name="input_storage_class_volume_type"></a> [storage\_class\_volume\_type](#input\_storage\_class\_volume\_type) | EBS volume type of the StorageClass. | `string` | `"gp3"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every AWS resource created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_controller_namespace"></a> [controller\_namespace](#output\_controller\_namespace) | Kubernetes namespace of the controller. |
| <a name="output_controller_release_name"></a> [controller\_release\_name](#output\_controller\_release\_name) | Helm release name of the controller (null if not installed by this module). |
| <a name="output_ebs_csi_role_arn"></a> [ebs\_csi\_role\_arn](#output\_ebs\_csi\_role\_arn) | ARN of the EBS CSI driver IAM role (null if install\_ebs\_csi\_driver is false). |
| <a name="output_github_config_secret_name"></a> [github\_config\_secret\_name](#output\_github\_config\_secret\_name) | Name of the Kubernetes secret holding the GitHub credentials. |
| <a name="output_runner_namespace"></a> [runner\_namespace](#output\_runner\_namespace) | Kubernetes namespace the runner scale sets are deployed in. |
| <a name="output_runner_scale_sets"></a> [runner\_scale\_sets](#output\_runner\_scale\_sets) | Map of deployed runner scale sets, keyed like var.runner\_scale\_sets:<br/>name (use in `runs-on:`), helm release name, runner service account and<br/>IAM role ARN (null if no AWS permissions were requested). |
| <a name="output_storage_class_name"></a> [storage\_class\_name](#output\_storage\_class\_name) | Name of the StorageClass created by this module (null if create\_storage\_class is false). |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
