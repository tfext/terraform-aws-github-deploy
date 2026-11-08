# terraform-aws-github-deploy

Wire one GitHub repository's environment to deploy one environment of an application

In the repository, it creates:

- The GitHub environment (the Terraform workspace by default), deployable from the default branch
  only, with optional required reviewers.
- Environment variables: `AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `TERRAFORM_PATH` and
  `DISPATCH_APP_ID`.
- The environment secret `DISPATCH_APP_PRIVATE_KEY`, read from Secrets Manager, so workflows can
  mint a GitHub App token and dispatch the Terraform Apply workflow. It's stored in Terraform's
  state.

In AWS, it creates the role `github-<repository><name_suffix>`, trusting the repository's
environment through the account's GitHub Actions OIDC provider. It can push to and pull from
`ecr_repository_arn`, and pull from `promote_from_repository_arn`.

Needs the `aws` and `github` providers. The `github` provider's token needs administration
(environments), secrets and variables permissions on the repository.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `repository` | `string` | required | GitHub repository name, in the provider's owner |
| `environment` | `string` | `null` | GitHub environment name. Defaults to the Terraform workspace |
| `name_suffix` | `string` | `""` | Suffix for the role name, such as the tagging module's `environment_suffix` |
| `ecr_repository_arn` | `string` | required | ECR repository the environment's workflows push to |
| `promote_from_repository_arn` | `string` | `null` | ECR repository the workflows can pull from, to promote its images |
| `terraform_path` | `string` | required | Terraform unit that deploys the environment, passed to the Apply workflow |
| `oidc_provider_arn` | `string` | required | The account's GitHub Actions OIDC provider |
| `dispatch_app_secret_id` | `string` | required | Secrets Manager secret holding the dispatch GitHub App, as `{"app_id": ..., "private_key": ...}` |
| `reviewers` | `object({ teams, users })` | `null` | Team and user ids, one of whom has to approve each deployment |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | The role the environment's workflows assume |
| `environment` | GitHub environment name |
