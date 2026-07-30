locals {
  ec2_runner_ssm_association = [
    {
      name = "AWS-UpdateSSMAgent"
    },
    {
      name = aws_ssm_document.dependencies.name
    }
  ]

  # Name for the EC2 instance and its derived IAM/SG/SSM resources. Kept
  # deterministic (no random suffix): arc-ec2 uses this name inside a for_each
  # key for its inline IAM policies, so it must be known at plan time.
  ec2_name                   = "${var.namespace}-${var.environment}-github-runner"
  runner_name                = var.runner_name != null ? var.runner_name : local.ec2_name
  aws_friendly_runner_labels = replace(var.runner_labels, ",", " + ")
}
