################################################################################
## defaults
################################################################################
terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }
}

module "tags" {
  source      = "sourcefuse/arc-tags/aws"
  version     = "1.2.5"
  environment = var.environment
  project     = "terraform-aws-refarch-github-runner"

  extra_tags = {
    Example = "True"
  }
}

provider "aws" {
  region = var.region
}

################################################################################
## lookups
################################################################################
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = var.vpc_names
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = var.private_subnet_names
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

## GitHub PAT stored as an SSM SecureString. This must be separate from the
## /github-runner/token parameter the root module creates for registration.
data "aws_ssm_parameter" "github_token" {
  name            = var.github_token_ssm_path
  with_decryption = true
}

################################################################################
## runner
################################################################################
module "runner" {
  source = "../../"

  namespace     = var.namespace
  environment   = var.environment
  region        = var.region
  subnet_id     = local.private_subnet_ids[0]
  vpc_id        = data.aws_vpc.this.id
  instance_type = "t3.micro"
  ami = {
    id       = data.aws_ami.ubuntu.id
    owner_id = "099720109477"
  }
  github_token  = data.aws_ssm_parameter.github_token.value
  runner_labels = "example,${var.namespace},${var.environment}"

  tags = module.tags.tags
}
