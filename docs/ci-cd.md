# CI/CD operations and runner selection

## Pipeline entrypoints

| Platform | Branch / PR or MR | Manual plan | Manual apply selection |
| --- | --- | --- | --- |
| Jenkins Multibranch | Discover branches and PRs with the root `Jenkinsfile`; default `TF_ACTION=validate`. | Build protected `main` with `TF_ACTION=plan` and `TF_STACK`. | Build `main` with `TF_ACTION=apply`; review private plan and approve the Jenkins input step. |
| GitHub Actions | `pull_request` and push to `main` run `validate` without AWS credentials. | Run the `Terraform governance` workflow on `main` with `action=plan` and `stack`. | Dispatch on `main` with `action=apply` and `stack`; approve the `aws-organization-apply` environment after reviewing the private plan. |
| GitLab CI | Mirror the repository into GitLab; branch/MR pipelines run `validate`. | Run a pipeline on protected default branch with `TF_ACTION=plan` and `TF_STACK`. | Run a pipeline with `TF_ACTION=apply`; review the private plan and start the protected manual `apply` job. |

Choose exactly one platform for each apply run. The selection is made in that platform's UI at run time; the repository does not contain a permanent "active CI" variable. The other platforms may still validate commits. Do not trigger two apply pipelines for the same stack. A shared remote Terraform backend lock is the final concurrency guard across platforms; Jenkins `disableConcurrentBuilds`, GitHub `concurrency`, and GitLab `resource_group` only serialize within their own platform.

## Common execution contract

All three pipelines call `scripts/ci/terraform.sh`:

- `validate`: `terraform fmt -check -recursive`, then `init -backend=false` and `validate` for each implemented stack. Provider downloads may require network. An absent stack is reported as skipped, not passed.
- `plan <stack>`: only on protected `main` with a matching checkout commit and short-lived AWS plan identity. Store the exact binary plan and human-readable text in a private KMS-encrypted S3 bucket. Print only its private object location and SHA-256 to the CI log.
- `apply <stack>`: only after the platform's native approval, with a separate AWS apply identity. Download the plan from the same engine/run/stack/commit path, verify its SHA-256, and apply that saved plan. Store apply logs privately.

Plan files may contain secrets in cleartext even when terminal output masks them. The plan bucket must block public access, use KMS encryption and versioning, restrict readers to reviewers, restrict writers to plan/apply roles, and expire artifacts promptly. Keep backend state in its own protected bucket/key. Never upload binary plans, text plans, or apply logs as public GitHub/GitLab artifacts.

## Prerequisites before enabling a real plan/apply

1. Implement the `stacks/organization` and `stacks/identity-center` Terraform roots and their separately bootstrapped remote backend. Commit provider lockfiles. Plan/apply intentionally fail while `main.tf` is absent.
2. Create a private plan bucket and KMS key outside this stack. Supply `TF_PLAN_BUCKET` and `TF_PLAN_KMS_KEY` to each trusted CI job. Give reviewers a separate read-only path to inspect `<plan-key>.txt`.
3. Configure distinct short-lived plan and apply AWS roles. Plan can read state and AWS inventory and write encrypted plans; apply can read plans, write private logs, and change only the intended governance resources. Scope OIDC trust to the exact project/repository, protected branch, and environment where supported. Do not use long-lived AWS access keys.
4. Configure GitHub repository variables `AWS_REGION`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `TF_PLAN_BUCKET`, and `TF_PLAN_KMS_KEY`. Create `aws-organization-apply` with required reviewers, prevent self-review, and restrict deployment to `main`. Only after verifying those settings, set the environment-scoped variable `APPLY_GATE_ACK=configured`. A missing or unprotected environment must be treated as a deployment blocker.
5. Mirror the repository to GitLab. Install a runner tagged `terraform-governance` with Bash, Terraform, AWS CLI, and `sha256sum`. Configure protected variables `AWS_REGION`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `TF_PLAN_BUCKET`, and `TF_PLAN_KMS_KEY`. Protect the default branch and `aws-organization-apply` environment. GitLab protected environments require an eligible GitLab tier; disable the apply job if that control is unavailable. After verifying protection, set protected `APPLY_GATE_ACK=configured`. Adjust the ID-token audience for a self-managed GitLab issuer.
6. Create a Jenkins Multibranch Pipeline pointed at the protected repository. Install Linux agents labeled `terraform-validate`, `terraform-plan`, and `terraform-apply` with Terraform, AWS CLI, and `sha256sum`. Keep privileged plan/apply credentials and agents inaccessible to untrusted PR branches; use a trusted main-only deployment job or equivalent Jenkins authorization controls. Restrict the input approvers. Jenkins agents must receive short-lived AWS credentials without storing static keys in the repository. After verifying these controls, expose `APPLY_GATE_ACK=configured` only to the trusted apply agent/job.
7. Test a plan and rejected apply in a dedicated sandbox/test OU. Confirm the plan text is visible only to reviewers and that an unapproved or stale plan cannot apply.

## Trust and review limits

The script checks the CI engine, run ID, stack, commit, `main` branch, approval flag, and plan checksum. These checks prevent accidental cross-run plan use; they do not replace AWS role trust, CI environment protection, or a human reading the plan. A contributor who can modify trusted CI code or bypass branch protection can change these checks. Protect the default branch and require review for pipeline files and Terraform policy changes.

GitHub OIDC uses the configured repository/environment subject. GitLab OIDC uses a protected project/branch subject. Jenkins credential isolation depends on server configuration and cannot be proven by a `Jenkinsfile` alone. Public CI logs may reveal resource details, so the common script captures plan and apply output privately. An apply may fail if the state changed after planning; do not regenerate an unreviewed plan automatically.

## References

- [Jenkins Multibranch Pipeline](https://www.jenkins.io/doc/book/pipeline/multibranch/)
- [GitHub OIDC for AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [GitHub deployment reviews](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments)
- [GitLab manual and protected jobs](https://docs.gitlab.com/ci/jobs/job_control/)
- [GitLab OIDC for AWS](https://docs.gitlab.com/ci/cloud_services/aws/)
- [Terraform saved plans](https://developer.hashicorp.com/terraform/cli/commands/plan)
