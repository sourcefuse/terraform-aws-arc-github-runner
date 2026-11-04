output "runner_scale_sets" {
  description = <<-EOT
    Map of deployed runner scale sets, keyed like var.runner_scale_sets:
    name (use in `runs-on:`), helm release name, runner service account and
    IAM role ARN (null if no AWS permissions were requested).
  EOT
  value = {
    for k, v in local.scale_sets : k => {
      name                 = v.name
      release_name         = helm_release.scale_set[k].name
      service_account_name = v.service_account_name
      iam_role_arn         = try(aws_iam_role.runner[k].arn, null)
    }
  }
}

output "runner_namespace" {
  description = "Kubernetes namespace the runner scale sets are deployed in."
  value       = var.k8s_namespace
}

output "controller_namespace" {
  description = "Kubernetes namespace of the controller."
  value       = var.controller_namespace
}

output "controller_release_name" {
  description = "Helm release name of the controller (null if not installed by this module)."
  value       = try(helm_release.controller[0].name, null)
}

output "github_config_secret_name" {
  description = "Name of the Kubernetes secret holding the GitHub credentials."
  value       = local.github_config_secret_name
}

output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver IAM role (null if install_ebs_csi_driver is false)."
  value       = try(aws_iam_role.ebs_csi[0].arn, null)
}

output "storage_class_name" {
  description = "Name of the StorageClass created by this module (null if create_storage_class is false)."
  value       = try(kubernetes_storage_class_v1.this[0].metadata[0].name, null)
}
