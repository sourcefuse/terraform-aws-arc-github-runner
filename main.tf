################################################################################
## defaults
################################################################################
terraform {
  required_version = "~> 1.3, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

################################################################################
## ssh
################################################################################
module "ssh_key_pair" {
  source = "git::https://github.com/cloudposse/terraform-aws-key-pair?ref=0.18.3"

  namespace             = var.namespace
  stage                 = terraform.workspace
  name                  = "github-runner"
  ssh_public_key_path   = "${path.root}/secrets"
  generate_ssh_key      = "true"
  private_key_extension = ".pem"
  public_key_extension  = ".pub"

  tags = var.tags
}

################################################################################
## ec2
################################################################################
module "runner" {
  source = "git::https://github.com/cloudposse/terraform-aws-ec2-instance?ref=0.45.2"

  name         = "github-runner"
  namespace    = var.namespace
  stage        = var.environment
  ssh_key_pair = module.ssh_key_pair.key_name
  vpc_id       = var.vpc_id
  subnet       = var.subnet_id

  ## ami / size
  ami           = var.ami.id
  ami_owner     = var.ami.owner_id
  instance_type = var.ami.instance_type

  ## monitoring / ssm / volume
  monitoring                   = var.monitoring_enabled
  ssm_patch_manager_enabled    = var.ssm_patch_manager_enabled
  associate_public_ip_address  = var.associate_public_ip_address
  root_block_device_encrypted  = var.root_block_device_encrypted
  root_block_device_kms_key_id = var.root_block_device_kms_key_id
  root_volume_size             = var.root_volume_size
  root_volume_type             = var.root_volume_type
  volume_tags_enabled          = var.volume_tags_enabled

  ## security
  #  ssm_patch_manager_iam_policy_arn = aws_iam_role.ssm.arn
  security_group_rules = var.security_group_rules

  tags = var.tags
}

################################################################################
## iam
################################################################################
resource "aws_iam_role_policy_attachment" "runner" {
  for_each = toset(var.runner_iam_role_policy_arns)

  role       = module.runner.role
  policy_arn = each.value
}

################################################################################
## configuration
################################################################################
resource "random_string" "ssm" {
  length      = 5
  lower       = true
  numeric     = true
  min_numeric = 1
  special     = false
  upper       = false
}

resource "aws_ssm_document" "runner" {
  name          = "${var.namespace}-${var.environment}-gh-runner-ec2"
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Docker CE to Runner."

    mainSteps = [
      {
        name   = "installDockerCE"
        action = "aws:runShellScript"
        inputs = {
          runCommand = [
            "export DEBIAN_FRONTEND=noninteractive",
            "sudo su -",
            "apt-get update",
            "apt-get install -y ca-certificates curl gnupg lsb-release",
            "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
            "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
            "apt-get update",
            "apt-get install -y docker-ce docker-ce-cli containerd.io"
          ]
        }
      },
    ]
  })

  tags = merge(var.tags, tomap({
    Name = "${var.namespace}-${var.environment}-gh-runner-ec2"
  }))
}

resource "aws_ssm_association" "runner" {
  for_each = toset(local.runner_ssm_association)

  name             = each.value
  association_name = "${each.value}-${random_string.ssm.result}"

  targets {
    key    = "InstanceIds"
    values = [module.runner.id]
  }
}
