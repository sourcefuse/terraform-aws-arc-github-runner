output "runner_scale_sets" {
  description = "Deployed runner scale sets. Use `name` in a workflow's `runs-on:`."
  value       = module.github_runner.eks_runner_scale_sets
}

output "runner_namespace" {
  description = "Kubernetes namespace the runner scale sets are deployed in."
  value       = module.github_runner.eks_runner_namespace
}

output "controller_namespace" {
  description = "Kubernetes namespace the controller is deployed in."
  value       = module.github_runner.eks_controller_namespace
}

output "storage_class_name" {
  description = "StorageClass used for runner work volumes."
  value       = module.github_runner.eks_storage_class_name
}
