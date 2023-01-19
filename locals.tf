locals {
  ec2_runner_ssm_association = [
    {
      name = "AWS-UpdateSSMAgent"
    },
    {
      name = aws_ssm_document.runner.name
    }
  ]

  runner_name                = var.runner_name != null ? var.runner_name : "${var.namespace}-${var.environment}-github-runner-${random_string.runner.result}"
  aws_friendly_runner_labels = replace(var.runner_labels, ",", " + ")
}
