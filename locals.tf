locals {
  ec2_runner_ssm_association = [
    {
      name = "AWS-UpdateSSMAgent"
    },
    {
      name = aws_ssm_document.dependencies.name
    }
  ]

  runner_name                = var.runner_name != null ? var.runner_name : "${var.namespace}-${var.environment}-github-runner-${random_string.runner.result}"
  aws_friendly_runner_labels = replace(var.runner_labels, ",", " + ")
  docker_compose_default_template = base64encode(templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    runner_token  = data.aws_ssm_parameter.runner_token.value
    runner_owner  = var.github_owner
    runner_name   = local.runner_name
    runner_user   = var.runner_user
    runner_image  = var.runner_image
    runner_labels = var.runner_labels
    repos_or_orgs = var.repos_or_orgs
  }))
  docker_compose_config = var.docker_compose_yaml_override == null ? local.docker_compose_default_template : base64encode(var.docker_compose_yaml_override)
}
