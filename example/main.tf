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

    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
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

provider "null" {}

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

## this was manually obtained from github then added to ssm param.
data "aws_ssm_parameter" "github_token" {
  name = "/${var.namespace}/${var.environment}/github/token"
}

################################################################################
## runner
################################################################################
module "runner" {
  source = "../"

  namespace     = var.namespace
  environment   = var.environment
  region        = var.region
  subnet_id     = local.private_subnet_ids[0]
  vpc_id        = data.aws_vpc.this.id
  instance_type = "t2.micro"
  github_token  = data.aws_ssm_parameter.github_token.value
  runner_labels = "example,${var.namespace},${var.environment}"

  tags = module.tags.tags
}
