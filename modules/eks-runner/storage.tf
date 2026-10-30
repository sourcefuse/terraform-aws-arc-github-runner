################################################################################
## EBS CSI driver (IAM role + EKS managed add-on)
## Not needed on EKS Auto Mode (block storage is built in) or when the driver is
## already installed on the cluster.
################################################################################
locals {
  ebs_csi_namespace       = "kube-system"
  ebs_csi_service_account = "ebs-csi-controller-sa"
}

data "aws_iam_policy_document" "ebs_csi_assume" {
  count = var.install_ebs_csi_driver ? 1 : 0

  dynamic "statement" {
    for_each = var.iam_auth_type == "pod_identity" ? [1] : []

    content {
      sid     = "AllowEksPodIdentity"
      effect  = "Allow"
      actions = ["sts:AssumeRole", "sts:TagSession"]

      principals {
        type        = "Service"
        identifiers = ["pods.eks.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/kubernetes-namespace"
        values   = [local.ebs_csi_namespace]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/kubernetes-service-account"
        values   = [local.ebs_csi_service_account]
      }
    }
  }

  dynamic "statement" {
    for_each = var.iam_auth_type == "irsa" ? [1] : []

    content {
      sid     = "AllowIrsa"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [var.oidc_provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.oidc_provider_url}:sub"
        values   = ["system:serviceaccount:${local.ebs_csi_namespace}:${local.ebs_csi_service_account}"]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.oidc_provider_url}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = var.install_ebs_csi_driver ? 1 : 0

  name                 = "${local.name_prefix}-ebs-csi"
  path                 = var.iam_role_path
  permissions_boundary = var.iam_role_permissions_boundary
  assume_role_policy   = data.aws_iam_policy_document.ebs_csi_assume[0].json

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.iam_auth_type == "pod_identity" || var.oidc_provider_arn != null
      error_message = "oidc_provider_arn is required when iam_auth_type is \"irsa\"."
    }
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.install_ebs_csi_driver ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

## Grants the driver use of a customer managed KMS key for encrypted volumes.
data "aws_iam_policy_document" "ebs_csi_kms" {
  count = var.install_ebs_csi_driver && var.ebs_csi_kms_key_arn != null ? 1 : 0

  statement {
    sid       = "AllowGrantsForAwsResources"
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = [var.ebs_csi_kms_key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "AllowKeyUsage"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [var.ebs_csi_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ebs_csi_kms" {
  count = var.install_ebs_csi_driver && var.ebs_csi_kms_key_arn != null ? 1 : 0

  name   = "${local.name_prefix}-ebs-csi-kms"
  role   = aws_iam_role.ebs_csi[0].id
  policy = data.aws_iam_policy_document.ebs_csi_kms[0].json
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count = var.install_ebs_csi_driver && var.iam_auth_type == "pod_identity" ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.ebs_csi_namespace
  service_account = local.ebs_csi_service_account
  role_arn        = aws_iam_role.ebs_csi[0].arn

  tags = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.install_ebs_csi_driver ? 1 : 0

  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_addon_version
  service_account_role_arn = var.iam_auth_type == "irsa" ? aws_iam_role.ebs_csi[0].arn : null

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    aws_iam_role_policy.ebs_csi_kms,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

################################################################################
## storage class for runner work volumes ("kubernetes" container mode)
################################################################################
resource "kubernetes_storage_class_v1" "this" {
  count = var.create_storage_class ? 1 : 0

  metadata {
    name = var.storage_class_name

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = tostring(var.storage_class_is_default)
    }
  }

  storage_provisioner    = var.storage_class_provisioner
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = merge(
    {
      type      = var.storage_class_volume_type
      fsType    = "ext4"
      encrypted = "true"
    },
    var.ebs_csi_kms_key_arn == null ? {} : { kmsKeyId = var.ebs_csi_kms_key_arn }
  )

  depends_on = [aws_eks_addon.ebs_csi]
}
