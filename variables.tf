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
  description = "File name of the workflow that deploys the environment, such as deploy.yaml. Only it, on the default branch, can assume the role"
}

variable "manage_shared" {
  type        = bool
  default     = null
  description = "Manage the settings the repository's environments share: the OIDC claim template, the dispatch App's key, AWS_REGION, TERRAFORM_PATH and DISPATCH_APP_ID. Exactly one environment of a repository manages them. Defaults to true in the staging workspace only"
}

variable "name_suffix" {
  type        = string
  default     = ""
  nullable    = false
  description = "Suffix for the role name, github-<repository><suffix>, such as the tagging module's environment_suffix"
}

variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the ECR repository the environment's workflow pushes to"
}

variable "promote_from_repository_arn" {
  type        = string
  default     = null
  description = "ARN of an ECR repository the workflow can pull from, to promote its images"
}

variable "terraform_path" {
  type        = string
  description = "Path of the Terraform unit that deploys the application, passed to the Apply workflow"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the account's GitHub Actions OIDC provider"
}

variable "dispatch_app_secret_id" {
  type        = string
  default     = null
  description = "Secrets Manager secret holding the dispatch GitHub App, as {\"app_id\": ..., \"private_key\": ...}. Read only when manage_shared"
}
