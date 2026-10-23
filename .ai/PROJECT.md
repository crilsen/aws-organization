# Project

- **Name:** aws-organization
- **Objective:** Public Terraform portfolio project for AWS Organizations and IAM Identity Center governance.
- **Current state:** Architecture and implementation plan only; no Terraform stack or deployed infrastructure yet.
- **Source of scope:** `docs/project-plan.md`; informed by the earlier local `aws-security-organization/ORG.md` outline.
- **Identity source:** Microsoft Entra ID groups will be provisioned through SCIM and used for AWS assignments.
- **Publishing:** Public GitHub repository under `crilsen`, with no real IDs, secrets, or state.

## Boundaries

The project plans OUs, SCPs, RCPs, inline-only permission sets, and group/account assignments. Account creation, Entra federation setup, and state bootstrap are documented prerequisites for the first implementation.
