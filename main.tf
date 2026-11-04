################################################################################
## lookups
################################################################################
data "aws_caller_identity" "this" {}

################################################################################
## ec2 — self-hosted GitHub Actions runner (SourceFuse arc-ec2)
################################################################################
module "runner" {
  source  = "sourcefuse/arc-ec2/aws"
  version = "0.0.5"
  count   = local.create_ec2_runner ? 1 : 0

  name          = local.ec2_name
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id
  ami_id        = var.ami.id
  instance_type = var.instance_type

  associate_public_ip_address = var.associate_public_ip_address
  enable_detailed_monitoring  = var.monitoring_enabled

  root_block_device_data = {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    encrypted   = var.root_block_device_encrypted
    kms_key_id  = var.root_block_device_kms_key_id
  }

  # Egress-only security group. The runner reaches GitHub / SSM / package repos
  # outbound; there is no inbound path (access is via SSM Session Manager, not SSH).
  security_group_data = {
    create        = true
    name          = "${local.ec2_name}-sg"
    description   = "Self-hosted GitHub Actions runner"
    ingress_rules = []
    egress_rules = [
      {
        description = "All outbound (GitHub, SSM, package repositories)"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    ]
  }

  # Instance role (arc-ec2 builds the role + instance profile):
  #   - managed: SSM core, so the instance is SSM-managed (used for all provisioning)
  #   - inline:  read the registration token from SSM Parameter Store at runtime
  #              (SecureString -> AWS-managed SSM key, hence kms:Decrypt)
  instance_profile_data = {
    create              = true
    managed_policy_arns = var.ec2_runner_iam_role_policy_arns
    policy_documents = [
      {
        name = "${local.ec2_name}-token-read"
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
    ]
  }

  tags = merge(var.tags, tomap({
    GitHubRunnerName   = local.runner_name
    GitHubRunnerLabels = local.aws_friendly_runner_labels
  }))
}

################################################################################
## configuration
################################################################################
## Mint a fresh GitHub registration token and store it in SSM Parameter Store.
resource "null_resource" "prepare" {
  count = local.create_ec2_runner ? 1 : 0

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

  lifecycle {
    precondition {
      condition     = var.vpc_id != null && var.subnet_id != null && var.github_token != null
      error_message = "vpc_id, subnet_id and github_token are required when create_ec2_runner is true."
    }
  }
}

## Install host dependencies plus the tooling the pipeline jobs need
## (aws, kubectl, helm, terraform, git, node, docker). Runs immediately via the
## association below.
resource "aws_ssm_document" "dependencies" {
  count = local.create_ec2_runner ? 1 : 0

  name          = "${local.ec2_name}-dependencies"
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
            # Node.js — required on the host PATH by the hashicorp/setup-terraform
            # wrapper (a #!/usr/bin/env node script). GitHub-hosted runners ship node;
            # a self-hosted host does not, so without this every setup-terraform job
            # fails with "/usr/bin/env: 'node': No such file or directory" (exit 127).
            "if ! command -v node >/dev/null; then curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs; fi",
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
    Name = "${local.ec2_name}-dependencies"
  }))

  depends_on = [
    null_resource.prepare
  ]
}

resource "aws_ssm_association" "dependencies" {
  for_each = local.create_ec2_runner ? { for k, v in local.ec2_runner_ssm_association : k => v } : {}

  name             = each.value.name
  association_name = each.value.name

  targets {
    key    = "InstanceIds"
    values = [module.runner[0].id]
  }
}

## Download the official GitHub Actions runner, register it, and install it as a
## systemd service. We pin a current runner version and let systemd supervise it
## (config persists its own auto-refreshing credentials after the first register,
## so the short-lived registration token is only needed once). This avoids the
## container-image self-update failure that left the runner permanently Offline.
resource "aws_ssm_document" "runner_install" {
  count = local.create_ec2_runner ? 1 : 0

  name          = local.ec2_name
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
    Name = local.ec2_name
  }))
}

resource "aws_ssm_association" "runner_install" {
  count = local.create_ec2_runner ? 1 : 0

  name             = aws_ssm_document.runner_install[0].name
  association_name = aws_ssm_document.runner_install[0].name

  apply_only_at_cron_interval = true
  schedule_expression         = "at(${trimsuffix(timeadd(timestamp(), "150s"), "Z")})"

  targets {
    key    = "InstanceIds"
    values = [module.runner[0].id]
  }

  depends_on = [
    aws_ssm_association.dependencies
  ]
}

## remove runner from github on destroy
resource "null_resource" "cleanup" {
  count = local.create_ec2_runner ? 1 : 0

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

################################################################################
## EKS Runner
## Autoscaling, ephemeral runner scale sets on an existing EKS cluster using the
## official Actions Runner Controller charts.
################################################################################
module "eks_runner" {
  source = "./modules/eks-runner"

  count = local.create_eks_runner ? 1 : 0

  environment = var.environment
  namespace   = var.namespace

  # cluster (unset / null attributes fall back to the submodule defaults)
  cluster_name      = var.eks_runner_config.cluster_name
  oidc_provider_arn = var.eks_runner_config.oidc_provider_arn
  name_prefix       = var.eks_runner_config.name_prefix

  # kubernetes placement
  k8s_namespace               = var.eks_runner_config.k8s_namespace
  create_k8s_namespace        = var.eks_runner_config.create_k8s_namespace
  k8s_namespace_labels        = var.eks_runner_config.k8s_namespace_labels
  controller_namespace        = var.eks_runner_config.controller_namespace
  create_controller_namespace = var.eks_runner_config.create_controller_namespace

  # helm charts
  install_controller         = var.eks_runner_config.install_controller
  controller_service_account = var.eks_runner_config.controller_service_account
  chart_oci_registry         = var.eks_runner_config.chart_oci_registry
  chart_version              = var.eks_runner_config.chart_version
  controller_release_name    = var.eks_runner_config.controller_release_name
  controller_values          = var.eks_runner_config.controller_values
  helm_timeout               = var.eks_runner_config.helm_timeout
  helm_max_history           = var.eks_runner_config.helm_max_history

  # runner scale sets
  github_config_url = var.eks_runner_config.github_config_url
  runner_scale_sets = var.eks_runner_config.runner_scale_sets

  # github authentication
  existing_github_config_secret_name = var.eks_runner_config.existing_github_config_secret_name
  github_auth_method                 = var.eks_runner_config.github_auth_method
  github_token                       = var.github_token
  github_app_id                      = var.eks_runner_config.github_app_id
  github_app_installation_id         = var.eks_runner_config.github_app_installation_id
  github_app_private_key             = var.github_app_private_key

  # iam for runner pods and the ebs csi driver
  iam_auth_type                 = var.eks_runner_config.iam_auth_type
  iam_role_path                 = var.eks_runner_config.iam_role_path
  iam_role_permissions_boundary = var.eks_runner_config.iam_role_permissions_boundary

  # storage
  install_ebs_csi_driver    = var.eks_runner_config.install_ebs_csi_driver
  ebs_csi_addon_version     = var.eks_runner_config.ebs_csi_addon_version
  ebs_csi_kms_key_arn       = var.eks_runner_config.ebs_csi_kms_key_arn
  create_storage_class      = var.eks_runner_config.create_storage_class
  storage_class_name        = var.eks_runner_config.storage_class_name
  storage_class_is_default  = var.eks_runner_config.storage_class_is_default
  storage_class_provisioner = var.eks_runner_config.storage_class_provisioner
  storage_class_volume_type = var.eks_runner_config.storage_class_volume_type

  tags = var.tags
}

################################################################################
