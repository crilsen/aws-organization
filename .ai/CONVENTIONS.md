# Conventions

- Documentation and future code comments: English, chosen by the user for this task.
- Context maintenance: automatic, chosen by the user for this repository.
- AWS display names: lowercase kebab case, `cn-org-<kind>-<scope>-<purpose>` where applicable.
- Terraform resource labels and map keys: snake case.
- Permission sets: inline policies only; do not add managed policy attachments.
- Example files: placeholders only. Never commit account IDs, group IDs, tenant IDs, credentials, plans with sensitive values, or Terraform state.
- Keep `AGENTS.md` as the routing entrypoint and `.ai/` as concise project context. `docs/project-plan.md` owns the architectural plan; do not duplicate its details here.

The naming and module layout are proposed design decisions, not evidence of an existing deployment.
