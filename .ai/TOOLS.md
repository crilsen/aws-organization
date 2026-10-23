# Tools

- Local `terraform` and `git` are available.
- Local `gh` exists. `gh auth status` reported an invalid default token at initial inspection on 2026-10-23, but `gh repo create ... --push` succeeded with an authenticated path. Verify authentication for each future write.
- GitHub connector supports repository search and file operations, but repository creation was not found among its available operations at initial inspection.
- No AWS credentials or backend configuration were observed. Never run `terraform apply` or `destroy` without explicit authorization.
- `terraform fmt`, offline `init -backend=false`, and `validate` will be safe once stacks exist. Keep plan/apply separate from documentation work.

See `.ai/GUARDRAILS.md` for action restrictions.
