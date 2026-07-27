locals {
  ec2_runner_ssm_association = [
    {
      name = "AWS-UpdateSSMAgent"
    },
    {
      name = aws_ssm_document.dependencies.name
    }
  ]

  # Name for the EC2 instance and its derived IAM/SG/SSM resources.
  ec2_name                   = "${var.namespace}-${var.environment}-github-runner-${random_string.runner.result}"
  runner_name                = var.runner_name != null ? var.runner_name : local.ec2_name
  aws_friendly_runner_labels = replace(var.runner_labels, ",", " + ")
}
