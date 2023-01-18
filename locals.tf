locals {
  runner_ssm_association = [
    "AWS-UpdateSSMAgent",
    aws_ssm_document.runner.name
  ]
}
