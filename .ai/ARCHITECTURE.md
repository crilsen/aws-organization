# Architecture

## Proposed design

`docs/project-plan.md` is the source of truth for the proposed architecture. Two Terraform stacks are planned: organization hierarchy/policies and Identity Center permission sets/assignments. They use separate state and change review. Existing organization, accounts, Identity Center instance, and Entra-provisioned groups are inputs to adopt or import, never assumed safe to recreate.

OUs: security, infrastructure, workloads (production and nonproduction), and sandbox. SCPs constrain principals in member accounts. RCPs constrain supported resources in member accounts. Neither constrains the management account.

Every permission set policy is a single inline document. Entra owns group membership; Terraform owns AWS account assignments. No Terraform infrastructure code or CI exists yet.
