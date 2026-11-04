################################################################################
## shared
################################################################################
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
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
## network
################################################################################
variable "vpc_names" {
  type        = list(string)
  description = "Private subnet names to add the runner"
  default     = ["arc-poc-vpc"]
}

variable "private_subnet_names" {
  type        = list(string)
  description = "Private subnet names to add the runner"
  default = [
    "arc-poc-private-subnet-private-us-east-1a",
    "arc-poc-private-subnet-private-us-east-1b"
  ]
}

################################################################################
## github
################################################################################
variable "github_token_ssm_path" {
  type        = string
  description = "SSM SecureString path holding the GitHub PAT. Keep this separate from the root module's /github-runner/token registration parameter."
  default     = "/arc/poc/github-runner/token"
}
