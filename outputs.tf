################################################################################
## EC2 Runner
################################################################################
output "ec2_runner_instance_id" {
  description = "Instance ID of the EC2 Runner"
  value       = var.create_ec2_runner ? module.runner[0].id : null
}

output "ec2_runner_instance_name" {
  description = "Instance Name of the EC2 Runner"
  value       = var.create_ec2_runner ? local.ec2_name : null
}

output "ec2_runner_role" {
  description = "Instance role name (created by arc-ec2 as <name>-role)"
  value       = var.create_ec2_runner ? "${local.ec2_name}-role" : null
}

output "ec2_runner_role_arn" {
  description = "Instance role ARN"
  value       = var.create_ec2_runner ? "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/${local.ec2_name}-role" : null
}

################################################################################
## EKS Runner
################################################################################
output "eks_runner_scale_sets" {
  description = "Deployed EKS runner scale sets: name (use in `runs-on:`), Helm release, runner service account and IAM role ARN."
  value       = var.eks_runner_config.create ? module.eks_runner[0].runner_scale_sets : null
}

output "eks_runner_namespace" {
  description = "Kubernetes namespace of the EKS runner scale sets."
  value       = var.eks_runner_config.create ? module.eks_runner[0].runner_namespace : null
}

output "eks_controller_namespace" {
  description = "Kubernetes namespace of the Actions Runner Controller."
  value       = var.eks_runner_config.create ? module.eks_runner[0].controller_namespace : null
}

output "eks_github_config_secret_name" {
  description = "Kubernetes secret holding the GitHub credentials of the EKS runners."
  value       = var.eks_runner_config.create ? module.eks_runner[0].github_config_secret_name : null
}

output "eks_ebs_csi_role_arn" {
  description = "IAM role ARN of the EBS CSI driver (null if not installed)."
  value       = var.eks_runner_config.create ? module.eks_runner[0].ebs_csi_role_arn : null
}

output "eks_storage_class_name" {
  description = "StorageClass created for runner work volumes (null if not created)."
  value       = var.eks_runner_config.create ? module.eks_runner[0].storage_class_name : null
}
