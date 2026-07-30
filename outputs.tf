output "ec2_runner_instance_id" {
  description = "Instance ID of the EC2 Runner"
  value       = module.runner.id
}

output "ec2_runner_instance_name" {
  description = "Instance Name of the EC2 Runner"
  value       = local.ec2_name
}

output "ec2_runner_role" {
  description = "Instance role name (created by arc-ec2 as <name>-role)"
  value       = "${local.ec2_name}-role"
}

output "ec2_runner_role_arn" {
  description = "Instance role ARN"
  value       = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/${local.ec2_name}-role"
}
