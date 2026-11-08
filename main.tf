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

data "aws_secretsmanager_secret_version" "dispatch_app" {
  secret_id = var.dispatch_app_secret_id
}

locals {
  environment    = coalesce(var.environment, terraform.workspace)
  ecr_repository = regex("repository/(.+)$", var.ecr_repository_arn)[0]
  dispatch_app   = jsondecode(data.aws_secretsmanager_secret_version.dispatch_app.secret_string)
  push_and_pull  = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
  pull           = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]
}

//
//  The GitHub environment, deployable from the default branch only
//
resource "github_repository_environment" "environment" {
  repository  = var.repository
  environment = local.environment

  dynamic "reviewers" {
    for_each = var.reviewers == null ? [] : [var.reviewers]
    content {
      teams = reviewers.value.teams
      users = reviewers.value.users
    }
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "default_branch" {
  repository     = var.repository
  environment    = github_repository_environment.environment.environment
  branch_pattern = data.github_repository.repository.default_branch
}

//
//  The role the environment's workflows assume: push to this environment's
//  repository, and pull from the one it promotes from
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
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${data.github_repository.repository.full_name}:environment:${local.environment}"]
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
//  What the environment's workflows need to push images and start a deploy
//
locals {
  variables = {
    AWS_ROLE_ARN    = aws_iam_role.deploy.arn
    AWS_REGION      = data.aws_region.current.region
    ECR_REPOSITORY  = local.ecr_repository
    TERRAFORM_PATH  = var.terraform_path
    DISPATCH_APP_ID = tostring(local.dispatch_app.app_id)
  }
}

resource "github_actions_environment_variable" "variables" {
  for_each = local.variables

  repository    = var.repository
  environment   = github_repository_environment.environment.environment
  variable_name = each.key
  value         = each.value
}

resource "github_actions_environment_secret" "dispatch_app_private_key" {
  repository      = var.repository
  environment     = github_repository_environment.environment.environment
  secret_name     = "DISPATCH_APP_PRIVATE_KEY"
  plaintext_value = local.dispatch_app.private_key
}
