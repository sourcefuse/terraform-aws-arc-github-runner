################################################################################
## shared
################################################################################
variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Name of the environment, i.e. dev, stage, prod"
  default     = "dev"
}

variable "namespace" {
  type        = string
  description = "Namespace of the project, i.e. arc"
  default     = "arc"
}

################################################################################
## eks
################################################################################
variable "cluster_name" {
  type        = string
  description = "Name of the existing EKS cluster to deploy the runners onto."
}

variable "iam_auth_type" {
  type        = string
  description = "How pods get IAM roles: \"pod_identity\" (needs the eks-pod-identity-agent add-on) or \"irsa\" (needs the cluster OIDC provider)."
  default     = "pod_identity"
}

variable "install_ebs_csi_driver" {
  type        = bool
  description = "Install the EBS CSI driver add-on. Set to false on EKS Auto Mode or if the driver is already installed."
  default     = true
}

################################################################################
## github
################################################################################
variable "github_config_url" {
  type        = string
  description = <<-EOT
    GitHub URL the runners register against. Organization URL
    (https://github.com/my-org), repository URL
    (https://github.com/my-org/my-repo), or enterprise URL
    (https://github.com/enterprises/my-enterprise).
  EOT
}

variable "github_token_ssm_path" {
  type        = string
  description = "SSM Parameter Store path (SecureString) holding the GitHub PAT used to register runners."
  default     = "/arc/dev/github/token"
}

################################################################################
## runner scaling
################################################################################
variable "min_runners" {
  type        = number
  description = "Minimum number of idle runners kept warm in the default scale set."
  default     = 0
}

variable "max_runners" {
  type        = number
  description = "Maximum number of runners per scale set."
  default     = 3
}

variable "runner_name" {
  type        = string
  description = "GitHub runner scale-set name used by workflows in `runs-on`."
  default     = "arc-poc-github-runner"
}
