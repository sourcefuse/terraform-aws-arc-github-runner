################################################################################
## defaults
################################################################################
terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20, < 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "tags" {
  source      = "sourcefuse/arc-tags/aws"
  version     = "1.2.5"
  environment = var.environment
  project     = "terraform-aws-arc-github-runner"

  extra_tags = {
    Example = "True"
  }
}

################################################################################
## lookups — existing EKS cluster the runners are deployed onto
################################################################################
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

## Only needed for IRSA. EKS Pod Identity does not use the OIDC provider.
data "aws_iam_openid_connect_provider" "this" {
  count = var.iam_auth_type == "irsa" ? 1 : 0
  url   = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

## GitHub PAT, manually seeded in SSM Parameter Store (SecureString). For
## production prefer a GitHub App, or `existing_github_config_secret_name` with
## External Secrets Operator so credentials never enter Terraform state.
data "aws_ssm_parameter" "github_token" {
  name            = var.github_token_ssm_path
  with_decryption = true
}

################################################################################
## providers — exec auth fetches a fresh token on every call, so long applies
## do not fail on the 15 minute EKS token expiry.
################################################################################
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}


provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name,
        "--region",
        var.region
      ]
    }
  }
}

################################################################################
## runners — GitHub Actions runner scale sets on EKS (root module, eks mode)
################################################################################
module "github_runner" {
  source = "../../"

  namespace   = var.namespace
  environment = var.environment
  region      = var.region

  # EKS runners only — no EC2 runner.
  create_ec2_runner = false

  # PAT sourced from SSM. For a GitHub App, set github_auth_method = "github_app",
  # github_app_id / github_app_installation_id below and github_app_private_key.
  github_token = data.aws_ssm_parameter.github_token.value

  eks_runner_config = {
    create             = true
    cluster_name       = var.cluster_name
    github_config_url  = var.github_config_url
    github_auth_method = "pat"

    # IAM for runner pods and the EBS CSI driver.
    iam_auth_type     = var.iam_auth_type
    oidc_provider_arn = try(data.aws_iam_openid_connect_provider.this[0].arn, null)

    # Persistent work volumes for the "kubernetes" container mode scale set.
    install_ebs_csi_driver = var.install_ebs_csi_driver
    create_storage_class   = true

    runner_scale_sets = {
      # General purpose pool: Docker-in-Docker for docker build/run jobs.
      default = {
        name           = "${var.namespace}-${var.environment}-github-runner"
        container_mode = "dind"
        min_runners    = var.min_runners
        max_runners    = var.max_runners
        resources = {
          requests = { cpu = "500m", memory = "1Gi" }
          limits   = { memory = "4Gi" }
        }
      }

      # Unprivileged pool: job containers run as separate pods (jobs must set
      # `container:`), with read-only ECR access granted via the pod's IAM role.
      k8s = {
        container_mode   = "kubernetes"
        min_runners      = 0
        max_runners      = var.max_runners
        work_volume_size = "10Gi"
        iam_policy_arns = {
          ecr_read = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        }
      }
    }
  }

  tags = module.tags.tags
}
