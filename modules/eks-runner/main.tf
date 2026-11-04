################################################################################
## namespaces
################################################################################
resource "kubernetes_namespace_v1" "controller" {
  count = var.install_controller && var.create_controller_namespace ? 1 : 0

  metadata {
    name   = var.controller_namespace
    labels = var.k8s_namespace_labels
  }
}

resource "kubernetes_namespace_v1" "runners" {
  count = var.create_k8s_namespace ? 1 : 0

  metadata {
    name   = var.k8s_namespace
    labels = var.k8s_namespace_labels
  }
}

################################################################################
## github credentials (pre-defined secret consumed by the scale set listener)
################################################################################
resource "kubernetes_secret_v1" "github_config" {
  count = local.create_github_config_secret ? 1 : 0

  metadata {
    name      = local.github_config_secret_name
    namespace = var.k8s_namespace
  }

  data = local.github_secret_data
  type = "Opaque"

  lifecycle {
    precondition {
      condition = (
        var.github_auth_method == "pat"
        ? (var.github_token != null && var.github_token != "")
        : (var.github_app_id != null && var.github_app_installation_id != null && var.github_app_private_key != null)
      )
      error_message = "Incomplete GitHub credentials: provide github_token for \"pat\", or github_app_id + github_app_installation_id + github_app_private_key for \"github_app\" (or set existing_github_config_secret_name)."
    }
  }

  depends_on = [kubernetes_namespace_v1.runners]
}

################################################################################
## controller (gha-runner-scale-set-controller)
################################################################################
resource "helm_release" "controller" {
  count = var.install_controller ? 1 : 0

  name       = var.controller_release_name
  repository = var.chart_oci_registry
  chart      = "gha-runner-scale-set-controller"
  version    = var.chart_version
  namespace  = var.controller_namespace

  timeout         = var.helm_timeout
  max_history     = var.helm_max_history
  wait            = true
  atomic          = true
  cleanup_on_fail = true

  values = concat(
    [yamlencode({
      serviceAccount = {
        create = true
        name   = local.controller_service_account.name
      }
    })],
    var.controller_values
  )

  depends_on = [kubernetes_namespace_v1.controller]
}

################################################################################
## runner scale sets (gha-runner-scale-set)
################################################################################
resource "helm_release" "scale_set" {
  for_each = local.scale_sets

  name       = each.value.name
  repository = var.chart_oci_registry
  chart      = "gha-runner-scale-set"
  version    = var.chart_version
  namespace  = var.k8s_namespace

  timeout         = var.helm_timeout
  max_history     = var.helm_max_history
  wait            = true
  atomic          = true
  cleanup_on_fail = true

  # Base configuration followed by user-supplied documents (later documents win).
  values = concat(
    [yamlencode(local.scale_set_values[each.key])],
    each.value.values
  )

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 53
      error_message = "Scale set name \"${each.value.name}\" exceeds 53 characters (Helm release name limit)."
    }
  }

  depends_on = [
    helm_release.controller,
    kubernetes_namespace_v1.runners,
    kubernetes_secret_v1.github_config,
    kubernetes_storage_class_v1.this,
    aws_eks_pod_identity_association.runner,
    aws_iam_role_policy_attachment.runner,
    aws_iam_role_policy.runner,
  ]
}
