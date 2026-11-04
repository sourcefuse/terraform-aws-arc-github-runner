locals {
  name_prefix = coalesce(var.name_prefix, "${var.namespace}-${var.environment}-github-runner")

  ## github credentials ---------------------------------------------------------
  create_github_config_secret = var.existing_github_config_secret_name == null
  github_config_secret_name   = coalesce(var.existing_github_config_secret_name, "${local.name_prefix}-github-config")

  # Keys exactly as the gha-runner-scale-set listener expects them.
  github_secret_data = var.github_auth_method == "pat" ? {
    github_token = var.github_token
    } : {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }

  ## controller -----------------------------------------------------------------
  # The controller service account name is set explicitly so scale sets can
  # bind to it deterministically instead of relying on chart discovery.
  controller_service_account = var.install_controller ? {
    name      = "${var.controller_release_name}-gha-rs-controller"
    namespace = var.controller_namespace
  } : var.controller_service_account

  ## iam ------------------------------------------------------------------------
  oidc_provider_url = var.oidc_provider_arn == null ? null : element(split("oidc-provider/", var.oidc_provider_arn), 1)

  ## scale sets -----------------------------------------------------------------
  scale_sets = {
    for k, v in var.runner_scale_sets : k => merge(v, {
      name = coalesce(v.name, "${local.name_prefix}-${k}")

      # Service account the chart creates for runner pods (gha-runner-scale-set
      # >= 0.13.0). IAM roles are bound to this name.
      service_account_name = format(
        "%s-%s",
        trimsuffix(substr("${coalesce(v.name, "${local.name_prefix}-${k}")}-gha-rs", 0, 63), "-"),
        contains(["kubernetes", "kubernetes-novolume"], v.container_mode) ? "kube-mode" : "no-permission"
      )

      create_iam_role = length(v.iam_policy_arns) > 0 || v.iam_policy_json != null

      work_volume_storage_class = try(coalesce(
        v.work_volume_storage_class,
        var.create_storage_class ? var.storage_class_name : null
      ), null)
    })
  }

  scale_sets_with_iam = { for k, v in local.scale_sets : k => v if v.create_iam_role }

  scale_set_policy_attachments = merge([
    for k, v in local.scale_sets_with_iam : {
      for policy_key, arn in v.iam_policy_arns : "${k}/${policy_key}" => {
        scale_set  = k
        policy_arn = arn
      }
    }
  ]...)

  # Helm values for each scale set, rendered as a single base YAML document.
  scale_set_values = {
    for k, v in local.scale_sets : k => merge(
      {
        githubConfigUrl    = coalesce(v.github_config_url, var.github_config_url)
        githubConfigSecret = local.github_config_secret_name
        runnerScaleSetName = v.name
        runnerGroup        = v.runner_group
        minRunners         = v.min_runners
        maxRunners         = v.max_runners

        template = {
          spec = merge(
            {
              containers = [
                merge(
                  {
                    name    = "runner"
                    image   = v.runner_image
                    command = ["/home/runner/run.sh"]
                  },
                  length(v.resources.requests) + length(v.resources.limits) > 0 ? {
                    resources = merge(
                      length(v.resources.requests) > 0 ? { requests = v.resources.requests } : {},
                      length(v.resources.limits) > 0 ? { limits = v.resources.limits } : {}
                    )
                  } : {}
                )
              ]
            },
            length(v.node_selector) > 0 ? { nodeSelector = v.node_selector } : {},
            length(v.tolerations) > 0 ? {
              tolerations = [
                for t in v.tolerations : {
                  for tk, tv in {
                    key               = t.key
                    operator          = t.operator
                    value             = t.value
                    effect            = t.effect
                    tolerationSeconds = t.toleration_seconds
                  } : tk => tv if tv != null
                }
              ]
            } : {}
          )
        }
      },
      local.controller_service_account == null ? {} : {
        controllerServiceAccount = local.controller_service_account
      },
      v.container_mode == "" ? {} : {
        containerMode = merge(
          { type = v.container_mode },
          v.container_mode == "kubernetes" ? {
            kubernetesModeWorkVolumeClaim = merge(
              {
                accessModes = ["ReadWriteOnce"]
                resources   = { requests = { storage = v.work_volume_size } }
              },
              v.work_volume_storage_class == null ? {} : { storageClassName = v.work_volume_storage_class }
            )
          } : {}
        )
      },
      # IRSA: annotate the chart-managed runner service account with the role.
      v.create_iam_role && var.iam_auth_type == "irsa" ? {
        resourceMeta = {
          (contains(["kubernetes", "kubernetes-novolume"], v.container_mode) ? "kubernetesModeServiceAccount" : "noPermissionServiceAccount") = {
            annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.runner[k].arn }
          }
        }
      } : {}
    )
  }
}
