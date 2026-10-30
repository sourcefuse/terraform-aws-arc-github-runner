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

variable "region" {
  type        = string
  description = "AWS region"
}

variable "tags" {
  type        = map(string)
  description = "Default tags to apply to every resource"
  default     = {}
}

################################################################################
## ec2 runner
################################################################################
variable "create_ec2_runner" {
  type        = bool
  description = "Whether to create the EC2 (SSM managed) runner. Set to false when only EKS runners are needed (eks_runner_config.create = true)."
  default     = true
}

################################################################################
## eks runner
################################################################################
variable "eks_runner_config" {
  nullable = false
  type = object({
    create            = optional(bool, false)
    cluster_name      = optional(string)
    github_config_url = optional(string)
    oidc_provider_arn = optional(string)
    name_prefix       = optional(string)

    k8s_namespace               = optional(string)
    create_k8s_namespace        = optional(bool)
    k8s_namespace_labels        = optional(map(string))
    controller_namespace        = optional(string)
    create_controller_namespace = optional(bool)

    install_controller = optional(bool)
    controller_service_account = optional(object({
      name      = string
      namespace = string
    }))
    chart_oci_registry      = optional(string)
    chart_version           = optional(string)
    controller_release_name = optional(string)
    controller_values       = optional(list(string))
    helm_timeout            = optional(number)
    helm_max_history        = optional(number)

    runner_scale_sets = optional(any)

    existing_github_config_secret_name = optional(string)
    github_auth_method                 = optional(string)
    github_app_id                      = optional(string)
    github_app_installation_id         = optional(string)

    iam_auth_type                 = optional(string)
    iam_role_path                 = optional(string)
    iam_role_permissions_boundary = optional(string)

    install_ebs_csi_driver    = optional(bool)
    ebs_csi_addon_version     = optional(string)
    ebs_csi_kms_key_arn       = optional(string)
    create_storage_class      = optional(bool)
    storage_class_name        = optional(string)
    storage_class_is_default  = optional(bool)
    storage_class_provisioner = optional(string)
    storage_class_volume_type = optional(string)
  })
  description = <<-EOT
    EKS runner configuration. Set `create = true` to deploy autoscaling, ephemeral
    runner scale sets on an existing EKS cluster (official Actions Runner
    Controller charts). Attributes map 1:1 to the inputs of
    [`modules/eks-runner`](./modules/eks-runner), where defaults, validation and
    full descriptions live. Unset attributes use the submodule defaults.
    Required when create = true: cluster_name, github_config_url.

    Credentials are passed separately as sensitive inputs: `github_token` (PAT)
    or `github_app_private_key` (GitHub App).

    Example:
      eks_runner_config = {
        create             = true
        cluster_name       = "my-eks-cluster"
        github_config_url  = "https://github.com/my-org"
        github_auth_method = "pat"
        runner_scale_sets = {
          default = { min_runners = 1, max_runners = 10 }
        }
      }
  EOT
  default = {
    create = false
  }

  validation {
    condition = !var.eks_runner_config.create || (
      try(length(var.eks_runner_config.cluster_name) > 0, false) &&
      try(length(var.eks_runner_config.github_config_url) > 0, false)
    )
    error_message = "eks_runner_config.cluster_name and eks_runner_config.github_config_url are required when eks_runner_config.create is true."
  }
}

################################################################################
## network
################################################################################
variable "vpc_id" {
  type        = string
  description = "VPC ID for EC2 instance to reside in. Required when create_ec2_runner is true."
  default     = null
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the EC2 instance to be assigned to. Required when create_ec2_runner is true."
  default     = null
}

################################################################################
## ec2
################################################################################
variable "ami" {
  description = "AMI information for the EC2 instance"
  type = object({
    id       = string
    owner_id = string
  })
  default = {
    id       = "ami-04505e74c0741db8d"
    owner_id = "099720109477"
  }
}

variable "instance_type" {
  description = "The instance type for the EC2 instance. Default is t3a.medium."
  type        = string
  default     = "t3a.medium"
}

variable "monitoring_enabled" {
  description = "Launched EC2 instance will have detailed monitoring enabled"
  type        = bool
  default     = true
}

variable "associate_public_ip_address" {
  description = "Associate a public IP address with the instance"
  type        = bool
  default     = false
}

variable "root_block_device_encrypted" {
  description = "Whether to encrypt the root block device"
  type        = bool
  default     = true
}

variable "root_block_device_kms_key_id" {
  description = "KMS key ID used to encrypt EBS volume. When specifying root_block_device_kms_key_id, root_block_device_encrypted needs to be set to true"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size of the root volume in gigabytes"
  type        = string
  default     = "80"
}

variable "root_volume_type" {
  description = "Type of root volume. Can be standard, gp2, gp3, io1 or io2"
  type        = string
  default     = "gp2"
}

################################################################################
## runner
################################################################################
variable "github_owner" {
  description = "GitHub Owner the runner belongs to. If you are adding a repo, the format will be `owner/repo`"
  type        = string
  default     = "sourcefuse"
}

variable "repos_or_orgs" {
  description = "Whether the API will register / deregister the runner in repos or orgs. Options are `orgs` and `repos`"
  type        = string
  default     = "orgs"
}

variable "runner_name" {
  description = "Name to assign the GitHub Runner. If no value is given, it will use the ec2 instance name."
  type        = string
  default     = null
}

variable "runner_version" {
  description = <<-EOT
    Version of the official GitHub Actions runner (github.com/actions/runner) to
    install on the host. Pin at or above GitHub's current minimum so the runner
    is never forced into a self-update. See the releases page for the latest tag.
  EOT
  type        = string
  default     = "2.336.0"
}

variable "runner_user" {
  description = "OS user that owns and runs the runner systemd service. Created if it does not exist."
  type        = string
  default     = "ubuntu"
}

variable "runner_labels" {
  description = <<-EOT
    Labels to assign the GitHub Runner. If no values are given, the default labels will be:
      - `self-hosted`
      - Base OS, i.e. `Linux`
      - Architecture, i.e. `X64`
    These labels cannot be overridden.
    Separate labels via comma, i.e. `dev,docker,another_label`
  EOT
  type        = string
  default     = ""
}

################################################################################
## security
################################################################################
variable "github_token" {
  description = <<-EOT
    GitHub Personal Access Token.
    - EC2 runner (create_ec2_runner): required, with `admin:org` scope. Used to obtain a runner registration token, see
      [Create a registration token for an organization](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-an-organization).
    - EKS runner (eks_runner_config.create): used when eks_runner_config.github_auth_method is "pat".
  EOT
  sensitive   = true
  type        = string
  default     = null
}

variable "github_app_private_key" {
  description = "GitHub App private key (PEM). Used by the EKS runner when eks_runner_config.github_auth_method is \"github_app\"."
  sensitive   = true
  type        = string
  default     = null
}

variable "ec2_runner_iam_role_policy_arns" {
  type        = list(string)
  description = "IAM role policies to attach to the Runner instance"
  default = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  ]
}
