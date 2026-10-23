# AWS Organization Governance with Terraform

Portfolio project plan for a multi-account AWS organization governed as code. The design covers organizational units, service control policies (SCPs), resource control policies (RCPs), IAM Identity Center permission sets, and account assignments for groups provisioned from Microsoft Entra ID.

**Status:** architecture and implementation plan. No AWS resources are deployed by this repository yet.

Read [the project plan](docs/project-plan.md) for the target architecture, naming rules, Terraform resources, delivery stages, acceptance criteria, and operational risks.

## Design principles

- Treat an existing organization and Identity Center instance as inputs to adopt or import. Never assume that a live organization can be recreated safely.
- Keep every permission set policy inline. Each permission set has one JSON document containing its allow and explicit deny statements; no AWS or customer managed policy attachments.
- Reference Entra-provisioned groups through the Identity Store. Terraform owns AWS account assignments, not workforce identities.
- Reserve admin, read-only, and operator for human identities. AI workloads use only a guarded AI authorization profile, with separate credentials and no management-account assignment. This boundary depends on keeping human credentials out of AI runtimes, including AWS CLI SSO caches.
- Manage SCPs and RCPs as separate policy types with staged attachments and documented exceptions.
- Run validation and plans in CI. Production apply requires a separate, reviewed execution path.

This is a public, sanitized design. Account IDs, tenant IDs, group IDs, credentials, state files, and company-specific names must stay outside the repository.
