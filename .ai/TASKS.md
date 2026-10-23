# Current Work

## Active

- None. The requested planning and publication are complete.

## Planned

- Implement the Terraform stacks and stages 1–5 from `docs/project-plan.md` incrementally after the plan is reviewed.
- Configure and test each CI platform's OIDC/short-lived AWS role, private plan bucket, remote state, and approval gate before enabling a real plan or apply.
- Collect private deployment inputs and exceptions before any live plan or apply.

## Completed

- Adopted the existing `.ai/` template for this project.
- Documented the target architecture, naming, security model, Entra contract, Terraform resources, stages, and risks.
- Published the plan to the public `crilsen/aws-organization` GitHub repository.
- Updated the plan to keep admin, read-only, and operator exclusive to human identities and to document AWS CLI credential reuse risk.
- Added Jenkins Multibranch, GitHub Actions, and GitLab CI pipelines with a shared Terraform script and run-time selection of the apply platform.
