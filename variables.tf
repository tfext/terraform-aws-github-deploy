variable "repository" {
  type        = string
  description = "GitHub repository name, in the provider's owner"
}

variable "environment" {
  type        = string
  default     = null
  description = "GitHub environment name. Defaults to the Terraform workspace"
}

variable "name_suffix" {
  type        = string
  default     = ""
  nullable    = false
  description = "Suffix for the role name, github-<repository><suffix>, such as the tagging module's environment_suffix"
}

variable "ecr_repository_arn" {
  type        = string
  description = "ARN of the ECR repository the environment's workflows push to"
}

variable "promote_from_repository_arn" {
  type        = string
  default     = null
  description = "ARN of an ECR repository the workflows can pull from, to promote its images"
}

variable "terraform_path" {
  type        = string
  description = "Path of the Terraform unit that deploys the environment, passed to the Apply workflow"
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the account's GitHub Actions OIDC provider"
}

variable "dispatch_app_secret_id" {
  type        = string
  description = "Secrets Manager secret holding the dispatch GitHub App, as {\"app_id\": ..., \"private_key\": ...}"
}

variable "reviewers" {
  type = object({
    teams = optional(list(number), [])
    users = optional(list(number), [])
  })
  default     = null
  description = "Team and user ids, one of whom has to approve each deployment to the environment"
}
