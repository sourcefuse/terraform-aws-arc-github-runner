locals {
  private_subnet_ids = [for k,v in data.aws_subnets.private.ids : v]
}
