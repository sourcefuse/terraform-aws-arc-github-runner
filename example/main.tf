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
  }
}

module "tags" {
  source = "git::https://github.com/sourcefuse/terraform-aws-refarch-tags.git?ref=1.1.0"

  environment = var.environment
  project     = "terraform-refarch-github-runner"

  extra_tags = {
    Example = "True"
  }
}

provider "aws" {
  region = var.region
}

################################################################
## lookups
################################################################
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["refarch${var.namespace}-${terraform.workspace}-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name = "tag:Name"
    values = [
      "refarch${var.namespace}-${terraform.workspace}-privatesubnet-private-${var.region}a",
      "refarch${var.namespace}-${terraform.workspace}-privatesubnet-private-${var.region}b"
    ]
  }
}

################################################################################
## runner
################################################################################
module "runner" {
  source = "../"

  namespace   = var.namespace
  environment = var.environment
  subnet_id   = data.aws_subnets.private.ids[0]
  vpc_id      = data.aws_vpc.this.id

  tags = module.tags.tags
}
