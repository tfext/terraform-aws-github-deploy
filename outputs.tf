output "role_arn" {
  value       = aws_iam_role.deploy.arn
  description = "ARN of the role the environment's workflow assumes"
}

output "variables" {
  value       = keys(local.variables)
  description = "Names of the Actions variables this environment set in the repository"
}
