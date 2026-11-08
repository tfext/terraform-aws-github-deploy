output "role_arn" {
  value       = aws_iam_role.deploy.arn
  description = "ARN of the role the environment's workflows assume"
}

output "environment" {
  value       = github_repository_environment.environment.environment
  description = "GitHub environment name"
}
