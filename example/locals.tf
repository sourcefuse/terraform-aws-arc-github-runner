locals {
  private_subnet_ids = [for k, v in toset(data.aws_subnets.private.ids) : v]
}
