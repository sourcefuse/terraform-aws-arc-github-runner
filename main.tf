################################################################################
## defaults / shared
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

    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
  }
}

resource "random_string" "runner" {
  length      = 4
  lower       = true
  numeric     = true
  min_numeric = 1
  special     = false
  upper       = false
}

################################################################################
## lookups
################################################################################
data "aws_caller_identity" "this" {}

data "aws_ssm_parameter" "runner_token" {
  name = "/${var.namespace}/${var.environment}/github-runner/token"

  depends_on = [
    null_resource.prepare
  ]
}

################################################################################
## ssh
################################################################################
module "ssh_key_pair" {
  source = "git::https://github.com/cloudposse/terraform-aws-key-pair?ref=0.18.3"

  namespace             = var.namespace
  stage                 = var.environment
  name                  = "github-runner-${random_string.runner.result}"
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

  name         = "github-runner-${random_string.runner.result}"
  namespace    = var.namespace
  stage        = var.environment
  ssh_key_pair = module.ssh_key_pair.key_name
  vpc_id       = var.vpc_id
  subnet       = var.subnet_id

  ## ami / size
  ami           = var.ami.id
  ami_owner     = var.ami.owner_id
  instance_type = var.instance_type

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
  security_group_rules = var.security_group_rules

  tags = merge(var.tags, tomap({
    GitHubRunnerName   = local.runner_name
    GitHubRunnerLabels = local.aws_friendly_runner_labels
  }))
}

################################################################################
## s3
################################################################################
## s3
resource "aws_s3_bucket" "runner" {
  bucket = module.runner.name

  object_lock_enabled = true

  tags = merge(var.tags, tomap({
    Name = module.runner.name
  }))
}

resource "aws_s3_bucket_server_side_encryption_configuration" "runner" {
  bucket = aws_s3_bucket.runner.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "runner" {
  bucket = aws_s3_bucket.runner.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "runner" {
  bucket = aws_s3_bucket.runner.id

  target_bucket = aws_s3_bucket.runner.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_acl" "runner" {
  bucket = aws_s3_bucket.runner.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "runner" {
  bucket = aws_s3_bucket.runner.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "docker_compose" {
  bucket = aws_s3_bucket.runner.id
  key    = "docker-compose.yml"

  content_base64 = base64encode(templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    runner_token        = data.aws_ssm_parameter.runner_token.value
    runner_organization = var.github_organization
    runner_name         = local.runner_name
    runner_labels       = var.runner_labels
  }))

  depends_on = [
    module.runner,
    null_resource.prepare
  ]
}

## iam access
resource "aws_iam_policy" "runner_bucket_access" {
  name = "${aws_s3_bucket.runner.id}-access"

  policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "kms:DescribeKey",
            "kms:GenerateDataKey",
            "kms:Encrypt",
            "kms:Decrypt"
          ],
          Resource = "arn:aws:kms:${var.region}:${data.aws_caller_identity.this.account_id}:alias/aws/s3" // s3 aws managed
        },
        {
          Effect = "Allow",
          Action = [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ],
          Resource = aws_s3_bucket.runner.arn
        },
        {
          Effect = "Allow",
          Action = [
            "s3:GetObjectAttributes",
            "s3:GetObject",
            "s3:PutObject",
            "s3:ListMultipartUploadParts",
            "s3:AbortMultipartUpload"
          ],
          Resource = "${aws_s3_bucket.runner.arn}/*"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "runner_bucket_access" {
  role       = module.runner.role
  policy_arn = aws_iam_policy.runner_bucket_access.arn
}

################################################################################
## iam
################################################################################
resource "aws_iam_role_policy_attachment" "runner" {
  for_each = toset(var.ec2_runner_iam_role_policy_arns)

  role       = module.runner.role
  policy_arn = each.value
}

################################################################################
## configuration
################################################################################
## get token for the runner
resource "null_resource" "prepare" {
  triggers = {
    namespace           = var.namespace
    environment         = var.environment
    github_token        = var.github_token
    github_organization = var.github_organization
    working_directory   = path.module
    get_runner_token    = "${path.module}/scripts/get-runner-token.sh"
  }

  provisioner "local-exec" {
    environment = {
      NAMESPACE           = self.triggers.namespace
      ENVIRONMENT         = self.triggers.environment
      GITHUB_TOKEN        = self.triggers.github_token
      GITHUB_ORGANIZATION = self.triggers.github_organization
      WORKING_DIRECTORY   = self.triggers.working_directory
    }
    command = <<-EOT
      ${self.triggers.get_runner_token} || true
    EOT
  }
}

## install host dependencies
resource "aws_ssm_document" "dependencies" {
  name          = "${module.runner.name}-dependencies"
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install host dependencies."

    mainSteps = [
      {
        name   = "installDependencies"
        action = "aws:runShellScript"
        inputs = {
          runCommand = [
            "export DEBIAN_FRONTEND=noninteractive",
            "export DOCKER_COMPOSE_URL=https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-$(uname -s | tr A-Z a-z)-$(uname -m)",
            "sudo su -",
            "apt-get update",
            "apt-get install -y ca-certificates curl gnupg lsb-release unzip",
            "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
            "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null",
            "apt-get update",
            "apt-get install -y docker-ce docker-ce-cli containerd.io",
            "curl -L \"$DOCKER_COMPOSE_URL\" -o /usr/local/bin/docker-compose",
            "chmod +x /usr/local/bin/docker-compose",
            "cd /tmp",
            "curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\"",
            "unzip awscliv2.zip",
            "[ -f \"/usr/local/bin/aws\" ] || ./aws/install"
          ]
        }
      },
    ]
  })

  tags = merge(var.tags, tomap({
    Name = "${module.runner.name}-dependencies"
  }))

  depends_on = [
    null_resource.prepare
  ]
}

resource "aws_ssm_association" "dependencies" {
  for_each = { for k, v in local.ec2_runner_ssm_association : k => v }

  name             = each.value.name
  association_name = each.value.name

  targets {
    key    = "InstanceIds"
    values = [module.runner.id]
  }
}

## download docker-compose then start container
resource "aws_ssm_document" "runner_compose" {
  name          = module.runner.name
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Download docker-compose.yml from S3 and start container."

    mainSteps = [
      {
        name   = "downloadThenStart"
        action = "aws:runShellScript"
        inputs = {
          runCommand = [
            "export DEBIAN_FRONTEND=noninteractive",
            "sudo su -",
            "mkdir -p /opt/github-runner",
            "cd /opt/github-runner/",
            "aws s3 cp s3://${aws_s3_bucket.runner.id}/docker-compose.yml .",
            "docker-compose up -d"
          ]
        }
      },
    ]
  })

  tags = merge(var.tags, tomap({
    Name = module.runner.name
  }))
}

resource "aws_ssm_association" "runner_compose" {
  name             = aws_ssm_document.runner_compose.name
  association_name = aws_ssm_document.runner_compose.name

  apply_only_at_cron_interval = true
  schedule_expression         = "at(${trimsuffix(timeadd(timestamp(), "150s"), "Z")})" # TODO - do something better

  targets {
    key    = "InstanceIds"
    values = [module.runner.id]
  }

  lifecycle {
    ignore_changes = [
      schedule_expression
    ]
  }
}

## remove runner from github
resource "null_resource" "cleanup" {
  triggers = {
    github_token        = var.github_token
    runner_name         = local.runner_name
    github_organization = var.github_organization
    remove_runner       = "${path.module}/scripts/remove-runner.sh"
    working_directory   = path.module
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      GITHUB_TOKEN        = self.triggers.github_token
      GITHUB_RUNNER_NAME  = self.triggers.runner_name
      GITHUB_ORGANIZATION = self.triggers.github_organization
      WORKING_DIRECTORY   = self.triggers.working_directory
    }
    command = <<-EOT
      ${self.triggers.remove_runner} || true
    EOT
  }
}
