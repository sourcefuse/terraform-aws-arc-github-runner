################################################################################
## defaults
################################################################################
terraform {
  required_version = "~> 1.3, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

module "tags" {
  source = "git::https://github.com/sourcefuse/terraform-aws-refarch-tags.git?ref=1.1.0"

  environment = var.environment
  project     = "terraform-aws-refarch-github-runner"

  extra_tags = {
    Example = "True"
  }
}

provider "aws" {
  region = var.region
}

provider "random" {}

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

################################################################################
## runner
################################################################################
module "runner" {
  source = "../"

  namespace   = var.namespace
  environment = var.environment
  subnet_id   = local.private_subnet_ids[0]
  vpc_id      = data.aws_vpc.this.id

  tags = module.tags.tags
}
