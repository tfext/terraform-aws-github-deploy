terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.0"
    }
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "github_repository" "repository" {
  name = var.repository
}

# The owner's numeric id, for immutable subject claims (github_organization needs more token scopes)
data "github_rest_api" "owner" {
  endpoint = "orgs/${split("/", data.github_repository.repository.full_name)[0]}"
}

data "aws_ssm_parameter" "dispatch_app" {
  count           = local.dispatch ? 1 : 0
  name            = var.dispatch_app_parameter
  with_decryption = true
}

locals {
  environment       = coalesce(var.environment, terraform.workspace)
  manage_shared     = coalesce(var.manage_shared, local.environment == "staging")
  dispatch          = local.manage_shared && var.terraform_path != null
  suffix            = upper(local.environment)
  branches          = coalesce(var.branches, local.environment == "staging" ? ["*"] : [data.github_repository.repository.default_branch])
  ecr_repository    = var.ecr_repository_arn == null ? null : regex("repository/(.+)$", var.ecr_repository_arn)[0]
  account_id        = data.aws_caller_identity.current.account_id
  run_task_cluster  = var.run_task == null ? null : regex("cluster/(.+)$", var.run_task.cluster_arn)[0]
  site_bucket       = var.static_site == null ? null : regex("^arn:aws:s3:::(.+)$", var.static_site.bucket_arn)[0]
  site_distribution = var.static_site == null ? null : regex("distribution/(.+)$", var.static_site.distribution_arn)[0]
  push_and_pull     = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
  pull              = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]

  # The subjects of tokens from the workflow file on each allowed branch, with the repository's
  # claim template (below). Repositories with immutable subject claims name the owner and
  # repository with their ids
  owner = split("/", data.github_repository.repository.full_name)[0]
  repos = [
    data.github_repository.repository.full_name,
    "${local.owner}@${jsondecode(data.github_rest_api.owner.body).id}/${var.repository}@${data.github_repository.repository.repo_id}",
  ]
  subjects = flatten([
    for branch in local.branches : [
      for repo in local.repos :
      "repo:${repo}:ref:refs/heads/${branch}:job_workflow_ref:${data.github_repository.repository.full_name}/.github/workflows/${var.workflow}@refs/heads/${branch}"
    ]
  ])
}

//
//  Settings the repository's environments share, managed by one of them: the OIDC claim
//  template, the dispatch App's key (when the workflow dispatches the Apply workflow), and the
//  variables every environment uses
//
resource "github_actions_repository_oidc_subject_claim_customization_template" "repository" {
  count              = local.manage_shared ? 1 : 0
  repository         = var.repository
  use_default        = false
  include_claim_keys = ["repo", "context", "job_workflow_ref"]
}

resource "github_actions_secret" "dispatch_app_private_key" {
  count           = local.dispatch ? 1 : 0
  repository      = var.repository
  secret_name     = "DISPATCH_APP_PRIVATE_KEY"
  plaintext_value = jsondecode(data.aws_ssm_parameter.dispatch_app[0].value).private_key
}

//
//  The role the environment's workflow assumes: push to this environment's
//  repository, pull from the one it promotes from, and deploy a static site.
//  Only the workflow file, on the allowed branches, can assume it
//
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "github-${var.repository}${var.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "deploy" {
  dynamic "statement" {
    for_each = var.ecr_repository_arn == null && var.promote_from_repository_arn == null ? [] : [1]
    content {
      sid       = "EcrSignIn"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.ecr_repository_arn == null ? [] : [1]
    content {
      sid       = "PushAndPull"
      actions   = local.push_and_pull
      resources = [var.ecr_repository_arn]
    }
  }

  dynamic "statement" {
    for_each = var.promote_from_repository_arn == null ? [] : [1]
    content {
      sid       = "PullToPromote"
      actions   = local.pull
      resources = [var.promote_from_repository_arn]
    }
  }

  // A one-off task, such as a migration: start one task family on one cluster, follow it to the
  // end, and read what it wrote
  dynamic "statement" {
    for_each = var.run_task == null ? [] : [var.run_task]
    content {
      sid       = "RunTask"
      actions   = ["ecs:RunTask"]
      resources = ["arn:aws:ecs:${data.aws_region.current.region}:${local.account_id}:task-definition/${statement.value.task_family}:*"]
      condition {
        test     = "ArnEquals"
        variable = "ecs:cluster"
        values   = [statement.value.cluster_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.run_task == null ? [] : [var.run_task]
    content {
      sid       = "FollowTask"
      actions   = ["ecs:DescribeTasks"]
      resources = ["arn:aws:ecs:${data.aws_region.current.region}:${local.account_id}:task/${local.run_task_cluster}/*"]
    }
  }

  dynamic "statement" {
    for_each = var.run_task == null ? [] : [var.run_task]
    content {
      sid       = "PassTaskRoles"
      actions   = ["iam:PassRole"]
      resources = statement.value.pass_role_arns
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.run_task == null || length(var.run_task.read_bucket_arns) == 0 ? [] : [var.run_task]
    content {
      sid       = "ReadTaskOutput"
      actions   = ["s3:ListBucket", "s3:GetObject"]
      resources = flatten([for arn in statement.value.read_bucket_arns : [arn, "${arn}/*"]])
    }
  }

  // A static site: sync the build to the bucket's app/ prefix and invalidate the distribution
  dynamic "statement" {
    for_each = var.static_site == null ? [] : [var.static_site]
    content {
      sid       = "ListSite"
      actions   = ["s3:ListBucket"]
      resources = [statement.value.bucket_arn]
    }
  }

  dynamic "statement" {
    for_each = var.static_site == null ? [] : [var.static_site]
    content {
      sid       = "SyncSite"
      actions   = ["s3:PutObject", "s3:DeleteObject"]
      resources = ["${statement.value.bucket_arn}/app/*"]
    }
  }

  dynamic "statement" {
    for_each = var.static_site == null ? [] : [var.static_site]
    content {
      sid       = "InvalidateSite"
      actions   = ["cloudfront:CreateInvalidation"]
      resources = [statement.value.distribution_arn]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json

  lifecycle {
    precondition {
      condition     = var.ecr_repository_arn != null || var.promote_from_repository_arn != null || var.static_site != null || var.run_task != null
      error_message = "Give the role something to deploy: ecr_repository_arn, static_site or run_task."
    }
  }
}

//
//  What the workflows need to push images, deploy a site and start a deploy.
//  Each environment's variables carry its name as a suffix, such as
//  AWS_ROLE_ARN_STAGING
//
locals {
  variables = merge(
    { "AWS_ROLE_ARN_${local.suffix}" = aws_iam_role.deploy.arn },
    var.ecr_repository_arn == null ? {} : { "ECR_REPOSITORY_${local.suffix}" = local.ecr_repository },
    var.static_site == null ? {} : {
      "SITE_BUCKET_${local.suffix}"       = local.site_bucket
      "SITE_DISTRIBUTION_${local.suffix}" = local.site_distribution
    },
    local.manage_shared ? { AWS_REGION = data.aws_region.current.region } : {},
    local.dispatch ? {
      TERRAFORM_PATH  = var.terraform_path
      DISPATCH_APP_ID = tostring(jsondecode(data.aws_ssm_parameter.dispatch_app[0].value).app_id)
    } : {}
  )
}

resource "github_actions_variable" "variables" {
  for_each = local.variables

  repository    = var.repository
  variable_name = each.key
  value         = each.value
}
