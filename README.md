# terraform-aws-github-deploy

Wire one GitHub repository to deploy one environment of an application, without GitHub
environments, so it works on any GitHub plan.

In AWS, it creates the role `github-<repository><name_suffix>`. It can push to and pull from
`ecr_repository_arn`, and pull from `promote_from_repository_arn`. It trusts one workflow file
(`workflow`) on the repository's default branch, through the account's GitHub Actions OIDC
provider, so a workflow on another branch, or another workflow file, can't assume it.

In the repository, it creates Actions variables, with the environment's name as a suffix on those
that differ per environment:

| Variable | Set by |
|---|---|
| `AWS_ROLE_ARN_<ENVIRONMENT>`, such as `AWS_ROLE_ARN_STAGING` | Every environment |
| `ECR_REPOSITORY_<ENVIRONMENT>` | Every environment |
| `AWS_REGION`, `TERRAFORM_PATH`, `DISPATCH_APP_ID` | The environment that manages the shared settings |

The environment that manages the shared settings (`manage_shared`, the `staging` workspace by
default) also creates:

- The Actions secret `DISPATCH_APP_PRIVATE_KEY`, read from Secrets Manager, so workflows can mint
  a GitHub App token and dispatch the Terraform Apply workflow. It's stored in Terraform's state.
- The repository's OIDC subject claim template, `repo`, `context` and `job_workflow_ref`, which
  puts the workflow file in the token's subject for the roles to trust.

Exactly one environment of a repository manages the shared settings.

Needs the `aws` and `github` providers. The `github` provider's token needs administration,
secrets and variables permissions on the repository, and read access to the organization.

```hcl
module "github_deploy" {
  source                      = "github.com/tfext/terraform-aws-github-deploy?ref=<tag>"
  repository                  = "propraize"
  workflow                    = module.tagging.production ? "promote.yaml" : "deploy.yaml"
  name_suffix                 = module.tagging.environment_suffix
  ecr_repository_arn          = module.ecr.arn
  promote_from_repository_arn = module.tagging.production ? local.staging_ecr_arn : null
  terraform_path              = "apps/propraize"
  oidc_provider_arn           = local.github_oidc_provider_arn
  dispatch_app_secret_id      = "ppta/github-dispatch-app"
}
```

The role trusts both forms of the subject: a repository with immutable subject claims names its
owner and itself with their ids (`repo:owner@123/name@456:...`), and an older one by name.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `repository` | `string` | required | GitHub repository name, in the provider's owner |
| `workflow` | `string` | required | File name of the workflow that deploys the environment, such as `deploy.yaml`. Only it, on the default branch, can assume the role |
| `environment` | `string` | `null` | Environment name, the suffix of its variables. Defaults to the Terraform workspace |
| `manage_shared` | `bool` | `null` | Manage the settings the repository's environments share. Defaults to `true` in the `staging` workspace only |
| `name_suffix` | `string` | `""` | Suffix for the role name, such as the tagging module's `environment_suffix` |
| `ecr_repository_arn` | `string` | required | ECR repository the environment's workflow pushes to |
| `promote_from_repository_arn` | `string` | `null` | ECR repository the workflow can pull from, to promote its images |
| `terraform_path` | `string` | required | Terraform unit that deploys the application, passed to the Apply workflow |
| `oidc_provider_arn` | `string` | required | The account's GitHub Actions OIDC provider |
| `dispatch_app_secret_id` | `string` | `null` | Secrets Manager secret holding the dispatch GitHub App, as `{"app_id": ..., "private_key": ...}`. Read only when managing the shared settings |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | The role the environment's workflow assumes |
| `variables` | Names of the Actions variables this environment set in the repository |
