# Validation

## Current plan stage

- Check documentation links, naming examples, and absence of real identifiers or secrets.
- Confirm that the project plan names the requested profiles, inline-only policies, Entra group assignments, SCPs, RCPs, and staged rollout.
- Check Git working tree and public repository visibility after publication.
- Parse GitHub/GitLab CI YAML, run `bash -n` and `shellcheck` on the common CI script, run credential-free validation, and verify plan/apply fail when stacks or approval prerequisites are absent.

## Future Terraform stages

- `terraform fmt -check -recursive`
- `terraform init -backend=false` in each implemented stack (provider download may still require network)
- `terraform validate` in each stack
- Policy JSON checks and tests for destructive-action denies and assignment restrictions
- `terraform plan` only with authorized credentials and a safely configured backend

Never claim a Terraform validation or AWS deployment until code and credentials exist and those checks have actually run.
