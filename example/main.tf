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
    name = "tag:Name"
    values = var.private_subnet_names
  }
}

#data "aws_subnet" "private" {
#  for_each = toset(data.aws_subnets.private.ids)
#  id       = each.value
#}

################################################################################
## runner
################################################################################
module "runner" {
  source = "../"

  namespace   = var.namespace
  environment = var.environment
  subnet_id   = "subnet-08857bbfad7bc9769" #local.private_subnet_ids[0]
  vpc_id      = data.aws_vpc.this.id

  tags = module.tags.tags
}
