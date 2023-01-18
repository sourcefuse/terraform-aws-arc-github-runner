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
  type = list(string)
  description = "Private subnet names to add the runner"
  default = ["arc-dev-vpc"]
}

variable "private_subnet_names" {
  type = list(string)
  description = "Private subnet names to add the runner"
  default = [
    "arc-dev-private-us-east-1a",
    "arc-dev-private-us-east-1b"
  ]
}
