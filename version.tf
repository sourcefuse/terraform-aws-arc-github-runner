terraform {
  # >= 1.5: required by sourcefuse/arc-ec2 (EC2 runner).
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }

    # Only used when eks_runner_config.create = true (modules/eks-runner).
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 4.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20, < 4.0"
    }
  }
}
