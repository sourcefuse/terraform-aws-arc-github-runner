output "ec2_runner_instance_id" {
  description = "Instance ID of the EC2 Runner"
  value       = module.runner.id
}

output "ec2_runner_instance_name" {
  description = "Instance Name of the EC2 Runner"
  value       = module.runner.name
}
