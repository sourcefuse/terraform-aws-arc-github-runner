locals {
  ec2_runner_ssm_association = [
    {
      name = "AWS-UpdateSSMAgent"
    },
    {
      name = aws_ssm_document.runner.name
    }
  ]

  aws_friendly_runner_labels = replace(var.runner_labels, ",", " + ")
}
