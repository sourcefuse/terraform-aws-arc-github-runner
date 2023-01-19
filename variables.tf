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
## network
################################################################################
variable "vpc_id" {
  type        = string
  description = "VPC ID for EC2 instance to reside in"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the EC2 instance to be assigned to"
}

################################################################################
## ec2
################################################################################
variable "ami" {
  description = "AMI information for the EC2 instance"
  type = object({
    id            = string
    owner_id      = string
    instance_type = string
  })
  default = {
    id            = "ami-04505e74c0741db8d"
    owner_id      = "099720109477"
    instance_type = "t3a.medium"
  }
}

variable "monitoring_enabled" {
  description = "Launched EC2 instance will have detailed monitoring enabled"
  type        = bool
  default     = true
}

variable "ssm_patch_manager_enabled" {
  description = "Whether to enable SSM Patch manager"
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

variable "volume_tags_enabled" {
  description = "Whether or not to copy instance tags to root and EBS volumes"
  type        = bool
  default     = true
}

################################################################################
## runner
################################################################################
variable "runner_token" {
  description = "GitHub Runner token used for registering the runner to the Organization."
  sensitive   = true
  type        = string
}

variable "runner_organization" {
  description = "GitHub Organization the runner belongs to."
  type        = string
  default     = "sourcefuse"
}

variable "runner_name" {
  description = "Name to assign the GitHub Runner. If no value is given, it will use the ec2 instance name."
  type        = string
  default     = null
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
variable "security_group_rules" {
  description = "Security group rules for the EC2 instance running the GitHub Runner"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

variable "ec2_runner_iam_role_policy_arns" {
  type        = list(string)
  description = "IAM role policies to attach to the Runner instance"
  default = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  ]
}
