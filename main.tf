################################################################################
## defaults / shared
################################################################################
terraform {
  required_version = "~> 1.3, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
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
## iam
################################################################################
# Base policies for the instance (SSM core, etc.).
resource "aws_iam_role_policy_attachment" "runner" {
  for_each = toset(var.ec2_runner_iam_role_policy_arns)

  role       = module.runner.role
  policy_arn = each.value
}

# The install step reads the registration token from SSM Parameter Store at
# runtime using the instance profile, so the short-lived token never has to be
# baked into a document. SecureString params are encrypted with the AWS-managed
# SSM key, hence the kms:Decrypt grant.
resource "aws_iam_role_policy" "runner_token_read" {
  name = "${module.runner.name}-token-read"
  role = module.runner.role

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ssm:GetParameter"],
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.this.account_id}:parameter/${var.namespace}/${var.environment}/github-runner/token"
      },
      {
        Effect   = "Allow",
        Action   = ["kms:Decrypt"],
        Resource = "arn:aws:kms:${var.region}:${data.aws_caller_identity.this.account_id}:alias/aws/ssm"
      }
    ]
  })
}

################################################################################
## configuration
################################################################################
## Mint a fresh GitHub registration token and store it in SSM Parameter Store.
resource "null_resource" "prepare" {
  triggers = {
    # Refresh the runner registration token on EVERY apply. GitHub registration
    # tokens expire in ~1h; with static triggers this ran only on the first
    # apply, so re-registration later failed with 404. timestamp() forces a
    # fresh token each apply.
    always_run        = timestamp()
    namespace         = var.namespace
    environment       = var.environment
    github_token      = var.github_token
    github_owner      = var.github_owner
    repos_or_orgs     = var.repos_or_orgs
    working_directory = path.module
    get_runner_token  = "${path.module}/scripts/get-runner-token.sh"
  }

  provisioner "local-exec" {
    environment = {
      NAMESPACE         = self.triggers.namespace
      ENVIRONMENT       = self.triggers.environment
      GITHUB_TOKEN      = self.triggers.github_token
      GITHUB_OWNER      = self.triggers.github_owner
      REPOS_OR_ORGS     = self.triggers.repos_or_orgs
      WORKING_DIRECTORY = self.triggers.working_directory
    }
    // || true --> to avoid output of sensitive values if it fails
    command = <<-EOT
      ${self.triggers.get_runner_token} || true
    EOT
  }
}

## Install host dependencies plus the tooling the pipeline jobs need
## (aws, kubectl, helm, terraform, git, docker). Runs immediately via the
## association below.
resource "aws_ssm_document" "dependencies" {
  name          = "${module.runner.name}-dependencies"
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install runner host dependencies and CI tooling."

    mainSteps = [
      {
        name   = "installDependencies"
        action = "aws:runShellScript"
        inputs = {
          runCommand = [
            "set -eux",
            "export DEBIAN_FRONTEND=noninteractive",
            "apt-get update",
            # Runner runtime deps (libicu for .NET) + general CI utilities.
            "apt-get install -y ca-certificates curl gnupg lsb-release unzip jq git tar libicu70 || apt-get install -y ca-certificates curl gnupg lsb-release unzip jq git tar libicu-dev",
            # AWS CLI v2
            "if ! command -v aws >/dev/null; then cd /tmp && curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && unzip -o awscliv2.zip && ./aws/install --update; fi",
            # kubectl (latest stable)
            "if ! command -v kubectl >/dev/null; then KV=$(curl -fsSL https://dl.k8s.io/release/stable.txt); curl -fsSL \"https://dl.k8s.io/release/$KV/bin/linux/amd64/kubectl\" -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl; fi",
            # helm
            "if ! command -v helm >/dev/null; then curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi",
            # terraform
            "if ! command -v terraform >/dev/null; then curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" > /etc/apt/sources.list.d/hashicorp.list && apt-get update && apt-get install -y terraform; fi",
            # docker (for jobs that build/run containers)
            "if ! command -v docker >/dev/null; then curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list && apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io && usermod -aG docker ${var.runner_user} || true; fi",
            "systemctl enable --now docker || true"
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

## Download the official GitHub Actions runner, register it, and install it as a
## systemd service. We pin a current runner version and let systemd supervise it
## (config persists its own auto-refreshing credentials after the first register,
## so the short-lived registration token is only needed once). This avoids the
## container-image self-update failure that left the runner permanently Offline.
resource "aws_ssm_document" "runner_install" {
  name          = module.runner.name
  document_type = "Command"
  target_type   = "/AWS::EC2::Instance"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and start the GitHub Actions runner as a systemd service."

    mainSteps = [
      {
        name   = "installRunner"
        action = "aws:runShellScript"
        inputs = {
          runCommand = [
            "set -eux",
            "RUNNER_DIR=/opt/actions-runner",
            "RUNNER_USER=${var.runner_user}",
            "RUNNER_VERSION=${var.runner_version}",
            "GH_URL=https://github.com/${var.github_owner}",
            # Already configured (e.g. re-run of the association) -> ensure the service is up and exit.
            "if [ -f \"$RUNNER_DIR/.runner\" ]; then (cd \"$RUNNER_DIR\" && ./svc.sh start || true); exit 0; fi",
            # Install the essentials the runner needs to download/register AND that
            # actions/checkout needs (git) BEFORE the runner comes Online. This makes
            # registration self-sufficient regardless of when the separate CI-tooling
            # association (aws/kubectl/helm/terraform) finishes, so the first job's
            # checkout can never lose a race against tool installation.
            "export DEBIAN_FRONTEND=noninteractive",
            "apt-get update -qq || true",
            "apt-get install -y -qq git curl tar unzip jq ca-certificates || true",
            "id -u \"$RUNNER_USER\" >/dev/null 2>&1 || useradd -m -s /bin/bash \"$RUNNER_USER\"",
            "mkdir -p \"$RUNNER_DIR\" && cd \"$RUNNER_DIR\"",
            "curl -fsSL -o runner.tar.gz \"https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz\"",
            "tar xzf runner.tar.gz && rm -f runner.tar.gz",
            "./bin/installdependencies.sh",
            "chown -R \"$RUNNER_USER\":\"$RUNNER_USER\" \"$RUNNER_DIR\"",
            # Fetch the fresh registration token minted by null_resource.prepare.
            "REG_TOKEN=$(aws ssm get-parameter --region ${var.region} --name /${var.namespace}/${var.environment}/github-runner/token --with-decryption --query Parameter.Value --output text)",
            "sudo -u \"$RUNNER_USER\" ./config.sh --unattended --replace --url \"$GH_URL\" --token \"$REG_TOKEN\" --name '${local.runner_name}' --labels '${var.runner_labels}' --work _work",
            # Install + start as a systemd service owned by the runner user.
            "./svc.sh install \"$RUNNER_USER\"",
            "./svc.sh start"
          ]
        }
      },
    ]
  })

  tags = merge(var.tags, tomap({
    Name = module.runner.name
  }))
}

resource "aws_ssm_association" "runner_install" {
  name             = aws_ssm_document.runner_install.name
  association_name = aws_ssm_document.runner_install.name

  apply_only_at_cron_interval = true
  schedule_expression         = "at(${trimsuffix(timeadd(timestamp(), "150s"), "Z")})"

  targets {
    key    = "InstanceIds"
    values = [module.runner.id]
  }

  depends_on = [
    aws_ssm_association.dependencies
  ]
}

## remove runner from github on destroy
resource "null_resource" "cleanup" {
  triggers = {
    github_token      = var.github_token
    runner_name       = local.runner_name
    github_owner      = var.github_owner
    repos_or_orgs     = var.repos_or_orgs
    working_directory = path.module
    remove_runner     = "${path.module}/scripts/remove-runner.sh"
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      GITHUB_TOKEN       = self.triggers.github_token
      GITHUB_RUNNER_NAME = self.triggers.runner_name
      GITHUB_OWNER       = self.triggers.github_owner
      REPOS_OR_ORGS      = self.triggers.repos_or_orgs
      WORKING_DIRECTORY  = self.triggers.working_directory
    }
    // || true --> to avoid output of sensitive values if it fails
    command = <<-EOT
      ${self.triggers.remove_runner} || true
    EOT
  }

  depends_on = [
    aws_ssm_association.runner_install
  ]
}
