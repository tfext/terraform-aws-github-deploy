variable "repository" {
  type        = string
  description = "GitHub repository name, in the provider's owner"
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment name, such as staging: the suffix of its variables (AWS_ROLE_ARN_STAGING). Defaults to the Terraform workspace"
}

variable "workflow" {
  type        = string
  description = "File name of the workflow that deploys the environment, such as deploy.yaml. Only it, on the branches in branches, can assume the role"
}

variable "branches" {
  type        = list(string)
  default     = null
  description = "Branches whose workflow file can assume the role, as IAM StringLike patterns. Defaults to [\"*\"] for staging, so any branch can deploy it, and the default branch otherwise"
}

variable "manage_shared" {
  type        = bool
  default     = null
  description = "Manage the settings the repository's environments share: the OIDC claim template, AWS_REGION, and with terraform_path the dispatch App's key, TERRAFORM_PATH and DISPATCH_APP_ID. Exactly one environment of a repository manages them. Defaults to true in the staging workspace only"
}

variable "name_suffix" {
  type        = string
  default     = ""
  nullable    = false
  description = "Suffix for the role name, github-<repository><suffix>, such as the tagging module's environment_suffix"
}

variable "ecr_repository_arn" {
  type        = string
  default     = null
  description = "ARN of the ECR repository the environment's workflow pushes to. Unset for a workflow that pushes no image, such as a static site's"
}

variable "promote_from_repository_arn" {
  type        = string
  default     = null
  description = "ARN of an ECR repository the workflow can pull from, to promote its images"
}

variable "terraform_path" {
  type        = string
  default     = null
  description = "Path of the Terraform unit that deploys the application, passed to the Apply workflow. Unset when the workflow doesn't dispatch the Apply workflow, which leaves out the dispatch App's key, TERRAFORM_PATH and DISPATCH_APP_ID"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the account's GitHub Actions OIDC provider"
}

variable "dispatch_app_parameter" {
  type        = string
  default     = null
  description = "SSM SecureString parameter holding the dispatch GitHub App, as {\"app_id\": ..., \"private_key\": ...}. Read only when manage_shared and terraform_path is set"
}

variable "run_task" {
  type = object({
    cluster_arn      = string
    task_family      = string
    pass_role_arns   = list(string)
    read_bucket_arns = optional(list(string), [])
  })
  default     = null
  description = "Lets the workflow start one task family on a cluster, wait for it, and read the buckets it writes to"
}

variable "static_site" {
  type = object({
    bucket_arn       = string
    distribution_arn = string
  })
  default     = null
  description = "Lets the workflow sync a built site to the bucket's app/ prefix and invalidate the distribution"
}
