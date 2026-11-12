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

data "github_repository" "repository" {
  name = var.repository
}

# The owner's numeric id, for immutable subject claims (github_organization needs more token scopes)
data "github_rest_api" "owner" {
  endpoint = "orgs/${split("/", data.github_repository.repository.full_name)[0]}"
}

data "aws_secretsmanager_secret_version" "dispatch_app" {
  count     = local.manage_shared ? 1 : 0
  secret_id = var.dispatch_app_secret_id
}

locals {
  environment    = coalesce(var.environment, terraform.workspace)
  manage_shared  = coalesce(var.manage_shared, local.environment == "staging")
  suffix         = upper(local.environment)
  branches       = coalesce(var.branches, local.environment == "staging" ? ["*"] : [data.github_repository.repository.default_branch])
  ecr_repository = regex("repository/(.+)$", var.ecr_repository_arn)[0]
  push_and_pull  = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
  pull           = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]

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
//  template, the dispatch App's key, and the variables every environment uses
//
resource "github_actions_repository_oidc_subject_claim_customization_template" "repository" {
  count              = local.manage_shared ? 1 : 0
  repository         = var.repository
  use_default        = false
  include_claim_keys = ["repo", "context", "job_workflow_ref"]
}

resource "github_actions_secret" "dispatch_app_private_key" {
  count           = local.manage_shared ? 1 : 0
  repository      = var.repository
  secret_name     = "DISPATCH_APP_PRIVATE_KEY"
  plaintext_value = jsondecode(data.aws_secretsmanager_secret_version.dispatch_app[0].secret_string).private_key
}

//
//  The role the environment's workflow assumes: push to this environment's
//  repository, and pull from the one it promotes from. Only the workflow file,
//  on the allowed branches, can assume it
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
  statement {
    sid       = "EcrSignIn"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PushAndPull"
    actions   = local.push_and_pull
    resources = [var.ecr_repository_arn]
  }

  dynamic "statement" {
    for_each = var.promote_from_repository_arn == null ? [] : [1]
    content {
      sid       = "PullToPromote"
      actions   = local.pull
      resources = [var.promote_from_repository_arn]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

//
//  What the workflows need to push images and start a deploy. Each
//  environment's variables carry its name as a suffix, such as
//  AWS_ROLE_ARN_STAGING
//
locals {
  variables = merge(
    {
      "AWS_ROLE_ARN_${local.suffix}"   = aws_iam_role.deploy.arn
      "ECR_REPOSITORY_${local.suffix}" = local.ecr_repository
    },
    local.manage_shared ? {
      AWS_REGION      = data.aws_region.current.region
      TERRAFORM_PATH  = var.terraform_path
      DISPATCH_APP_ID = tostring(jsondecode(data.aws_secretsmanager_secret_version.dispatch_app[0].secret_string).app_id)
    } : {}
  )
}

resource "github_actions_variable" "variables" {
  for_each = local.variables

  repository    = var.repository
  variable_name = each.key
  value         = each.value
}
