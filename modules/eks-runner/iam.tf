################################################################################
## trust policies
################################################################################
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

## EKS Pod Identity — scoped to the exact namespace / service account via the
## session tags EKS sets when it assumes the role.
data "aws_iam_policy_document" "runner_pod_identity_assume" {
  for_each = var.iam_auth_type == "pod_identity" ? local.scale_sets_with_iam : {}

  statement {
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
      values   = [var.k8s_namespace]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [each.value.service_account_name]
    }
  }
}

## IRSA — scoped to the exact service account and STS audience.
data "aws_iam_policy_document" "runner_irsa_assume" {
  for_each = var.iam_auth_type == "irsa" ? local.scale_sets_with_iam : {}

  statement {
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
      values   = ["system:serviceaccount:${var.k8s_namespace}:${each.value.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

################################################################################
## runner pod iam roles (one per scale set that requests AWS permissions)
################################################################################
resource "aws_iam_role" "runner" {
  for_each = local.scale_sets_with_iam

  name                 = "${each.value.name}-runner"
  path                 = var.iam_role_path
  permissions_boundary = var.iam_role_permissions_boundary
  assume_role_policy = (
    var.iam_auth_type == "pod_identity"
    ? data.aws_iam_policy_document.runner_pod_identity_assume[each.key].json
    : data.aws_iam_policy_document.runner_irsa_assume[each.key].json
  )

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.iam_auth_type == "pod_identity" || var.oidc_provider_arn != null
      error_message = "oidc_provider_arn is required when iam_auth_type is \"irsa\"."
    }
  }
}

resource "aws_iam_role_policy_attachment" "runner" {
  for_each = local.scale_set_policy_attachments

  role       = aws_iam_role.runner[each.value.scale_set].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "runner" {
  for_each = { for k, v in local.scale_sets_with_iam : k => v if v.iam_policy_json != null }

  name   = "${each.value.name}-runner"
  role   = aws_iam_role.runner[each.key].id
  policy = each.value.iam_policy_json
}

resource "aws_eks_pod_identity_association" "runner" {
  for_each = var.iam_auth_type == "pod_identity" ? local.scale_sets_with_iam : {}

  cluster_name    = var.cluster_name
  namespace       = var.k8s_namespace
  service_account = each.value.service_account_name
  role_arn        = aws_iam_role.runner[each.key].arn

  tags = var.tags
}
