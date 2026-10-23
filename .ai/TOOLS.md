# Tools

- Local `terraform` and `git` are available.
- Local `gh` exists. `gh auth status` reported an invalid default token at initial inspection on 2026-10-23, but `gh repo create ... --push` succeeded with an authenticated path. Verify authentication for each future write.
- GitHub connector supports repository search and file operations, but repository creation was not found among its available operations at initial inspection.
- No AWS credentials or backend configuration were observed. Never run `terraform apply` or `destroy` without explicit authorization.
- `terraform fmt`, `init -backend=false`, and `validate` are the safe stack checks once stacks exist. Provider downloads during init may require network. Keep plan/apply separate from documentation work.
- `scripts/ci/terraform.sh validate` is the common CI entrypoint. `plan` requires a configured stack, remote backend, short-lived AWS identity, and private plan bucket. `apply` additionally requires native CI approval and a platform administrator activation gate. Never set `CI_APPLY_GATE_ACK` for an unprotected job.

See `.ai/GUARDRAILS.md` for action restrictions.
