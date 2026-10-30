################################################################################
## shared
################################################################################
variable "environment" {
  type        = string
  description = "Name of the environment, i.e. dev, stage, prod"
}

variable "namespace" {
  type        = string
  description = "Namespace of the project, i.e. refarch"
}

variable "name_prefix" {
  type        = string
  description = <<-EOT
    Prefix used to name resources (Kubernetes secret, IAM roles, default scale
    set names). If null, defaults to `<namespace>-<environment>-github-runner`.
  EOT
  default     = null

  validation {
    condition     = var.name_prefix == null || can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric characters or '-', and start and end with an alphanumeric character."
  }
}

variable "tags" {
  type        = map(string)
  nullable    = false
  description = "Tags applied to every AWS resource created by this module."
  default     = {}
}

################################################################################
## cluster
################################################################################
variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the runners are deployed onto. Used for EKS Pod Identity associations and EKS add-ons."
}

variable "oidc_provider_arn" {
  type        = string
  description = <<-EOT
    ARN of the cluster's IAM OIDC provider. Required only when `iam_auth_type`
    is "irsa" and an IAM role is created (runner IAM policies or the EBS CSI
    driver).
  EOT
  default     = null

  validation {
    condition     = var.oidc_provider_arn == null || can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:oidc-provider/.+$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be a valid IAM OIDC provider ARN."
  }
}

################################################################################
## kubernetes placement
################################################################################
variable "k8s_namespace" {
  type        = string
  nullable    = false
  description = "Kubernetes namespace where the runner scale sets (and their pods) are deployed."
  default     = "arc-runners"
}

variable "create_k8s_namespace" {
  type        = bool
  nullable    = false
  description = "Whether this module creates the runner namespace. Set to false if it already exists."
  default     = true
}

variable "k8s_namespace_labels" {
  type        = map(string)
  nullable    = false
  description = <<-EOT
    Labels applied to the namespaces created by this module, e.g. Pod Security
    Admission labels. Note: "dind" container mode needs privileged pods.
  EOT
  default     = {}
}

variable "controller_namespace" {
  type        = string
  nullable    = false
  description = "Kubernetes namespace where the gha-runner-scale-set-controller is deployed."
  default     = "arc-systems"
}

variable "create_controller_namespace" {
  type        = bool
  nullable    = false
  description = "Whether this module creates the controller namespace (only used when install_controller is true)."
  default     = true
}

################################################################################
## helm charts (official Actions Runner Controller - gha-runner-scale-set)
################################################################################
variable "install_controller" {
  type        = bool
  nullable    = false
  description = <<-EOT
    Whether to install the gha-runner-scale-set-controller. Install exactly one
    controller per cluster; set to false when it is managed elsewhere and set
    `controller_service_account` instead.
  EOT
  default     = true
}

variable "controller_service_account" {
  type = object({
    name      = string
    namespace = string
  })
  description = <<-EOT
    Service account of an externally managed controller (install_controller =
    false). If null, the chart discovers it at install time.
  EOT
  default     = null
}

variable "chart_oci_registry" {
  type        = string
  nullable    = false
  description = "OCI registry base path hosting the official Actions Runner Controller Helm charts."
  default     = "oci://ghcr.io/actions/actions-runner-controller-charts"
}

variable "chart_version" {
  type        = string
  nullable    = false
  description = <<-EOT
    Version of both ARC charts (controller and scale set must match). Minimum
    supported: 0.13.0. Helm does not upgrade CRDs, so follow the ARC upgrade
    guide when changing minor versions.
  EOT
  default     = "0.15.1"

  validation {
    condition     = can(regex("^(0\\.(1[3-9]|[2-9][0-9])|[1-9][0-9]*\\.[0-9]+)\\.[0-9]+$", var.chart_version))
    error_message = "chart_version must be a semantic version >= 0.13.0 (e.g. 0.15.1)."
  }
}

variable "controller_release_name" {
  type        = string
  nullable    = false
  description = "Helm release name of the controller."
  default     = "arc"
}

variable "controller_values" {
  type        = list(string)
  nullable    = false
  description = "Additional raw YAML values documents merged into the controller release (later documents win)."
  default     = []
}

variable "helm_timeout" {
  type        = number
  nullable    = false
  description = "Seconds to wait for each Helm release to become ready."
  default     = 600
}

variable "helm_max_history" {
  type        = number
  nullable    = false
  description = "Maximum number of Helm release revisions kept per release."
  default     = 10
}

################################################################################
## runner scale sets
################################################################################
variable "github_config_url" {
  type        = string
  description = <<-EOT
    Default GitHub URL runners register against: an organization
    (https://github.com/my-org), repository (https://github.com/my-org/my-repo)
    or enterprise (https://github.com/enterprises/my-enterprise). Can be
    overridden per scale set.
  EOT

  validation {
    condition     = can(regex("^https://", var.github_config_url))
    error_message = "github_config_url must be an https:// URL."
  }
}

variable "runner_scale_sets" {
  type = map(object({
    name              = optional(string)
    github_config_url = optional(string)
    runner_group      = optional(string, "default")
    min_runners       = optional(number, 0)
    max_runners       = optional(number, 5)
    container_mode    = optional(string, "dind")

    runner_image = optional(string, "ghcr.io/actions/actions-runner:latest")
    resources = optional(object({
      requests = optional(map(string), {})
      limits   = optional(map(string), {})
    }), {})
    node_selector = optional(map(string), {})
    tolerations = optional(list(object({
      key                = optional(string)
      operator           = optional(string)
      value              = optional(string)
      effect             = optional(string)
      toleration_seconds = optional(number)
    })), [])

    work_volume_storage_class = optional(string)
    work_volume_size          = optional(string, "10Gi")

    iam_policy_arns = optional(map(string), {})
    iam_policy_json = optional(string)

    values = optional(list(string), [])
  }))
  nullable    = false
  description = <<-EOT
    Runner scale sets to deploy, keyed by a short identifier. Each scale set is a
    separate Helm release and autoscaling pool. Workflows target a scale set with
    `runs-on: <name>`.

    - name: scale set name (used in `runs-on:`). Defaults to `<name_prefix>-<key>`. Max 53 chars (Helm release name limit).
    - github_config_url: overrides the module-level github_config_url.
    - runner_group: GitHub runner group (must already exist for org/enterprise scopes).
    - min_runners / max_runners: idle runners kept warm / upper scaling bound.
    - container_mode: "dind", "kubernetes", "kubernetes-novolume" or "" (configure via values).
    - runner_image: runner container image. Pin a version or digest in production.
    - resources: runner container requests/limits, e.g. { requests = { cpu = "500m", memory = "1Gi" } }.
    - node_selector / tolerations: runner pod scheduling.
    - work_volume_storage_class / work_volume_size: work volume for "kubernetes" mode.
      Storage class defaults to the class created by this module, else the cluster default.
    - iam_policy_arns: map of static name => IAM policy ARN granted to runner pods.
    - iam_policy_json: inline IAM policy document granted to runner pods.
    - values: extra raw YAML values documents for this release (later documents win).
  EOT
  default = {
    default = {}
  }

  validation {
    condition     = length(var.runner_scale_sets) > 0
    error_message = "At least one runner scale set must be defined."
  }

  validation {
    condition = alltrue([
      for k, v in var.runner_scale_sets : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k))
    ])
    error_message = "runner_scale_sets keys must be lowercase alphanumeric characters or '-', and start and end with an alphanumeric character."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : v.name == null || can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", v.name))
    ])
    error_message = "runner_scale_sets[*].name must be lowercase alphanumeric characters or '-', and start and end with an alphanumeric character."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : v.min_runners >= 0 && floor(v.min_runners) == v.min_runners
    ])
    error_message = "runner_scale_sets[*].min_runners must be a whole number >= 0."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : v.max_runners >= 1 && floor(v.max_runners) == v.max_runners
    ])
    error_message = "runner_scale_sets[*].max_runners must be a whole number >= 1."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : v.min_runners <= v.max_runners
    ])
    error_message = "runner_scale_sets[*].min_runners must be less than or equal to max_runners."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : contains(["dind", "kubernetes", "kubernetes-novolume", ""], v.container_mode)
    ])
    error_message = "runner_scale_sets[*].container_mode must be one of: dind, kubernetes, kubernetes-novolume, or \"\"."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : v.github_config_url == null || can(regex("^https://", v.github_config_url))
    ])
    error_message = "runner_scale_sets[*].github_config_url must be an https:// URL."
  }

  validation {
    condition = alltrue(flatten([
      for v in var.runner_scale_sets : [
        for arn in values(v.iam_policy_arns) : can(regex("^arn:aws[a-zA-Z-]*:iam::([0-9]{12}|aws):policy/.+$", arn))
      ]
    ]))
    error_message = "runner_scale_sets[*].iam_policy_arns values must be valid IAM policy ARNs."
  }

  validation {
    condition = alltrue([
      for v in var.runner_scale_sets : v.iam_policy_json == null || can(jsondecode(v.iam_policy_json))
    ])
    error_message = "runner_scale_sets[*].iam_policy_json must be valid JSON."
  }
}

################################################################################
## github authentication
################################################################################
variable "existing_github_config_secret_name" {
  type        = string
  description = <<-EOT
    Name of an existing Kubernetes secret (in k8s_namespace) holding GitHub
    credentials, e.g. synced by External Secrets Operator. When set, the module
    does not create a secret and the credential inputs below are ignored. This
    keeps credentials out of Terraform state.
  EOT
  default     = null
}

variable "github_auth_method" {
  type        = string
  nullable    = false
  description = "GitHub authentication method: \"github_app\" (recommended) or \"pat\"."
  default     = "github_app"

  validation {
    condition     = contains(["pat", "github_app"], var.github_auth_method)
    error_message = "github_auth_method must be either \"pat\" or \"github_app\"."
  }
}

variable "github_token" {
  type        = string
  description = "GitHub Personal Access Token (github_auth_method = \"pat\"). Prefer a fine-grained token scoped to the target org/repo."
  default     = null
  sensitive   = true
}

variable "github_app_id" {
  type        = string
  description = "GitHub App ID or client ID (github_auth_method = \"github_app\")."
  default     = null
}

variable "github_app_installation_id" {
  type        = string
  description = "GitHub App installation ID (github_auth_method = \"github_app\")."
  default     = null
}

variable "github_app_private_key" {
  type        = string
  description = "GitHub App private key in PEM format (github_auth_method = \"github_app\")."
  default     = null
  sensitive   = true
}

################################################################################
## aws iam (runner pods + ebs csi driver)
################################################################################
variable "iam_auth_type" {
  type        = string
  nullable    = false
  description = <<-EOT
    How pods get IAM roles: "pod_identity" (EKS Pod Identity, recommended;
    requires the eks-pod-identity-agent add-on, built in on EKS Auto Mode) or
    "irsa" (IAM Roles for Service Accounts; requires oidc_provider_arn).
  EOT
  default     = "pod_identity"

  validation {
    condition     = contains(["pod_identity", "irsa"], var.iam_auth_type)
    error_message = "iam_auth_type must be either \"pod_identity\" or \"irsa\"."
  }
}

variable "iam_role_path" {
  type        = string
  nullable    = false
  description = "Path for IAM roles created by this module."
  default     = "/"
}

variable "iam_role_permissions_boundary" {
  type        = string
  description = "ARN of a permissions boundary applied to IAM roles created by this module."
  default     = null
}

################################################################################
## storage (ebs csi driver + storage class)
################################################################################
variable "install_ebs_csi_driver" {
  type        = bool
  nullable    = false
  description = <<-EOT
    Install the aws-ebs-csi-driver EKS add-on with an IAM role. Needed for
    persistent work volumes ("kubernetes" mode) on clusters without EKS Auto
    Mode. Leave false on Auto Mode or if the driver is already installed.
  EOT
  default     = false
}

variable "ebs_csi_addon_version" {
  type        = string
  description = "Version of the aws-ebs-csi-driver add-on. If null, the cluster's default version is used."
  default     = null
}

variable "ebs_csi_kms_key_arn" {
  type        = string
  description = "Customer managed KMS key the EBS CSI driver may use for volume encryption. If null, the AWS managed key is used."
  default     = null
}

variable "create_storage_class" {
  type        = bool
  nullable    = false
  description = "Whether to create an encrypted EBS StorageClass for runner work volumes."
  default     = false
}

variable "storage_class_name" {
  type        = string
  nullable    = false
  description = "Name of the StorageClass created when create_storage_class is true."
  default     = "arc-runner-gp3"
}

variable "storage_class_is_default" {
  type        = bool
  nullable    = false
  description = "Whether the created StorageClass is marked as the cluster default."
  default     = false
}

variable "storage_class_provisioner" {
  type        = string
  nullable    = false
  description = "CSI provisioner: \"ebs.csi.aws.com\" (EBS CSI add-on) or \"ebs.csi.eks.amazonaws.com\" (EKS Auto Mode)."
  default     = "ebs.csi.aws.com"

  validation {
    condition     = contains(["ebs.csi.aws.com", "ebs.csi.eks.amazonaws.com"], var.storage_class_provisioner)
    error_message = "storage_class_provisioner must be \"ebs.csi.aws.com\" or \"ebs.csi.eks.amazonaws.com\"."
  }
}

variable "storage_class_volume_type" {
  type        = string
  nullable    = false
  description = "EBS volume type of the StorageClass."
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.storage_class_volume_type)
    error_message = "storage_class_volume_type must be one of gp2, gp3, io1, io2, st1, sc1."
  }
}
