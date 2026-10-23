# Project plan: AWS Organization governance

## 1. Objective and scope

Build a public Terraform portfolio repository that demonstrates AWS multi-account governance. The first implementation should manage the organization hierarchy, SCPs, RCPs, IAM Identity Center permission sets, and assignments to groups synchronized from Microsoft Entra ID. The design is based on the earlier `aws-security-organization/ORG.md` outline, adjusted to use only inline permission-set policies and to add RCPs and guarded AI administration.

The repository must contain sanitized examples and tests. It must never create real accounts, change a live organization, or run `terraform apply` as part of CI. Account creation, Entra SAML/SCIM configuration, emergency access provisioning, and bootstrap of the remote state are documented prerequisites rather than part of the first delivery.

## 2. Target architecture

```text
AWS Organization (existing or explicitly bootstrapped)
├── management account: organization administration and Terraform state access
├── security OU
│   ├── log-archive account
│   └── security-tooling account
├── infrastructure OU
│   ├── network account
│   └── shared-services account
├── workloads OU
│   ├── production OU
│   └── nonproduction OU
└── sandbox OU

Microsoft Entra ID --SAML + SCIM--> IAM Identity Center
                                      ├── inline permission sets
                                      └── group × permission set × account assignments

SCP: limits principals in member accounts
RCP: limits access to supported resources in member accounts
```

The management account is deliberately separate: SCPs and RCPs do not constrain it. Keep workloads out of it, tightly restrict its assignments, and use an independently tested break-glass path. Existing accounts are mapped to OUs by account ID in private variables; the public examples use placeholders.

## 3. Repository structure

```text
README.md
docs/
  project-plan.md
  architecture.md
  naming.md
  policy-catalog.md
  operations.md
  entra-contract.md
modules/
  hierarchy/
  organization-policy/
  permission-set/
  account-assignment/
stacks/
  organization/
  identity-center/
examples/
  organization.auto.tfvars.example
  identity-center.auto.tfvars.example
tests/
  policies/
.github/workflows/
  terraform-checks.yml
.ai/
```

`modules/` are small reusable Terraform modules. `stacks/organization` and `stacks/identity-center` have separate state, provider configuration, and change review. Example files are documentation, never live values. Introduce files as stages are implemented; this tree is the target layout.

## 4. Naming contract

Use lowercase kebab case for AWS display names and snake case for Terraform addresses and map keys. Canonical pattern: `cn-org-<kind>-<scope>-<purpose>`; keep names within each AWS service limit. No names encode a person's name, tenant ID, or account ID.

| Kind | Examples | Rule |
| --- | --- | --- |
| OU | `security`, `infrastructure`, `workloads`, `production`, `nonproduction`, `sandbox` | Stable names; hierarchy provides context. |
| SCP | `cn-org-scp-root-protect-org`, `cn-org-scp-workloads-protect-logging` | Prefix `cn-org-scp`; scope and objective follow. |
| RCP | `cn-org-rcp-root-require-tls` | Prefix `cn-org-rcp`; use only supported services/resources. |
| Permission set | `cn-org-ps-admin`, `cn-org-ps-readonly`, `cn-org-ps-operator`, `cn-org-ps-ai-admin` | One inline policy per set. |
| Entra group | `aws-org-admins`, `aws-org-readonly`, `aws-org-operators`, `aws-org-ai-admins` | Contract for externally provisioned groups; AWS does not create them. |
| Terraform key | `protect_org`, `require_tls`, `ai_admin` | Snake case, stable across renames of display names. |

Tags on taggable resources: `project=aws-organization`, `managed-by=terraform`, `environment=<environment>`, `owner=<team>`. Some Organizations objects may not support tags; validate provider support per resource.

## 5. Permission-set model

| Profile | Intended use | Inline allow | Inline explicit deny | Assignment rule |
| --- | --- | --- | --- | --- |
| Admin | Human platform administrators only | Broad administrative access, with scope refined per account | Defense-in-depth denies for organization exit/closure and disabling core logging | Human-only Entra admin group; management account only by explicit separate approval. |
| Read-only | Human audit and troubleshooting only | Read/list/describe actions across approved services | Mutating actions absent | Human-only Entra read-only group; selected member accounts. |
| Operator | Human day-2 operations only | Curated operations on approved services/resources | IAM, Organizations, Identity Center, account closure, and security-control mutations | Human-only Entra operators group; workload accounts. |
| AI admin guarded | AI-driven administrative tasks only | Broad capability only in isolated member accounts | Explicit denies for deletion/termination, account closure, policy detachment, permission escalation, role assumption, and disabling logs/security services | Dedicated AI identity; sandbox or nonproduction only. No production or management assignment by default. |

All four policies are generated inline with `aws_iam_policy_document` and attached using exactly one `aws_ssoadmin_permission_set_inline_policy` per set. No `aws_ssoadmin_managed_policy_attachment` or customer-managed attachment belongs in the implementation. IAM Identity Center permits one inline policy per permission set and enforces size limits; policy generation must check both total and non-whitespace length. An AI admin deny list cannot guarantee protection from every destructive API, especially new APIs. Combine the inline deny with SCP protection, narrowly scoped account assignment, plan review, and human approval for apply. Do not describe this profile as a full administrator in security claims.

Session durations should start at 1 hour for admin and AI admin, and at 4 hours for read-only/operator, subject to the organization's requirements. Permission-set changes can trigger reprovisioning to assigned accounts; roll out gradually.

### Human-only access boundary, including the AWS CLI

The admin, read-only, and operator permission sets are **human-only**. AWS IAM Identity Center issues temporary credentials for an assigned permission set that work through the console, AWS CLI, and SDKs. A policy cannot reliably determine whether the caller is a person or an AI agent when both use the same credentials. In particular, `aws:UserAgent` is caller-controlled and is not an authorization boundary. Human-only does **not** mean console-only: authorized people may use the CLI, but agents must not receive their CLI credentials or SSO session cache.

Enforce the boundary at identity assignment and credential custody:

1. Entra human groups contain named workforce users only. AI identities and workload service principals are excluded; membership changes require a human approval process, with privileged access controls for admin membership.
2. Terraform allows the three human permission sets to be assigned only to the three declared human group keys. It rejects direct user assignments and any AI group → human permission-set pairing. An AI identity may receive only the guarded AI profile. Verify the effective assignments in AWS after each change.
3. Run AI agents in isolated environments with a dedicated AI credential source. Do not mount a person's `~/.aws`, SSO cache, browser session, environment variables, or copied temporary credentials into the agent runtime. A human using the AWS CLI must keep that session outside the AI execution environment.
4. The AI role must explicitly deny `sts:AssumeRole`, `iam:PassRole`, IAM privilege creation, Identity Center assignment administration, and Organizations policy administration unless a narrowly reviewed use case proves an exception. Test attempted role hopping and policy changes as negative cases.
5. Keep Terraform apply and permission-assignment changes behind a separate human-reviewed CI identity. Log and alert on use of human permission-set roles from unexpected execution environments; telemetry supports investigation but does not prove that a call was human.

For a supervised agent using IAM Identity Center, use a dedicated Entra-provisioned user assigned only to the AI group and guarded AI permission set. Do not use a human's Entra/SSO login for the agent. For a headless agent, use a separate short-lived workload identity (for example, OIDC into a dedicated IAM role) with the same or narrower guardrails; an Entra service principal must not be assumed to work as an IAM Identity Center workforce user. Keep that workload role out of the three human permission sets. The exact headless integration is a later design decision and must be validated before implementation.

If an AI agent can read or reuse a human's valid CLI/SDK credentials, it can exercise that human permission set. No permission-set policy or SCP can reliably distinguish the agent in that situation. This project will state that residual risk plainly and will not claim absolute technical prevention. The preventive requirement is credential separation plus exclusive assignments; the enforcement tests can verify assignments and isolated runtime configuration, not a caller's biological identity.

## 6. SCP and RCP strategy

| Policy | Type | Initial scope | Intent and rollout |
| --- | --- | --- | --- |
| `protect-org` | SCP | Test OU, then root | Deny member account exit and account closure; verify recovery and delegated administration. |
| `protect-logging` | SCP | Test OU, then member OUs | Deny CloudTrail and Config disable/delete actions. Test service and automation exceptions before broad attachment. |
| `protect-identity` | SCP | Test OU, then member OUs | Deny changes to designated break-glass and security roles except approved automation. Avoid brittle role-name assumptions. |
| `region-boundary` | SCP | Workloads test OU, then selected OUs | Restrict approved regions with explicit global-service exemptions and tested service behavior. |
| `require-tls` | RCP | Test OU, then selected member OUs | Deny insecure transport to supported resources such as S3; validate service principal exceptions and AWS-supported resource types. |
| `external-access-boundary` | RCP | Test OU only at first | Evaluate restricting access by organization ID for supported resource types. Document expected cross-organization integrations before expanding. |

Keep each policy in its own reviewed source file and use `aws_organizations_policy` with explicit `SERVICE_CONTROL_POLICY` or `RESOURCE_CONTROL_POLICY` type. Attach with `aws_organizations_policy_attachment`. Enable policy types explicitly only after prerequisites and testing. Retain AWS-managed `FullAWSAccess` / `RCPFullAWSAccess` behavior as required for deny-list strategy; never replace it casually. RCPs apply only to AWS-supported resources and do not cover the management account. SCPs constrain principals in member accounts and do not grant permission.

## 7. Entra integration contract

1. Entra owns users, group memberships, and group lifecycle. Configure SAML federation and SCIM provisioning outside this Terraform stack.
2. Wait until each required group exists in IAM Identity Center. Resolve the group through `aws_identitystore_group` using its stable external ID when available, or exact `DisplayName` with a uniqueness check.
3. Store the expected Entra group names/identifiers in private variables. Do not commit tenant IDs, SCIM tokens, or real group IDs.
4. Build account assignments from a map of `{group_key, permission_set_key, account_keys}`. Validate that all keys exist, reject AI-admin assignment to management or production, and reject AI-to-human or human-to-AI permission-set pairings by default.
5. Terraform owns only `aws_ssoadmin_account_assignment`; it never creates a second copy of a provisioned group.

Loss of SCIM sync or a group rename can break lookup and future plans; document ownership and recovery. A Terraform plan must fail on missing group rather than silently skip an assignment.

## 8. Terraform resources and data sources

| Area | Primary Terraform objects |
| --- | --- |
| Organization | `aws_organizations_organization` for a new, explicitly bootstrapped organization; `aws_organizations_organizational_unit`; `aws_organizations_account` only if a later, separately approved account-factory stage is added. Existing organizations/accounts use data sources or import. |
| Governance | `aws_organizations_policy`, `aws_organizations_policy_attachment` for SCP and RCP; organization roots and account lookups as data sources. |
| Identity Center | `aws_ssoadmin_instances` data source; `aws_ssoadmin_permission_set`; `aws_ssoadmin_permission_set_inline_policy`; `aws_identitystore_group` data source; `aws_ssoadmin_account_assignment`. |
| Policy JSON | `aws_iam_policy_document` data source or `jsonencode` with tests, never manually concatenated JSON. |
| State | S3 backend created independently; locking mechanism selected and verified against the installed Terraform and AWS provider versions before implementation. |

Use provider aliases only for resources that genuinely require different accounts or regions. Run Organizations operations in the management account with a narrowly scoped execution role; manage Identity Center in its home region. Use AWS CLI SSO locally or OIDC-based short-lived credentials in CI; never store static access keys.

## 9. Implementation stages and acceptance criteria

| Stage | Deliverable | Acceptance |
| --- | --- | --- |
| 0. Design and prerequisites | This plan, naming contract, account/OU inventory template, Entra group contract, threat and cost notes | Public files contain no real identifiers or secrets; owner approves the target organization and Identity Center instance. |
| 1. Terraform foundation | Provider/version constraints, separate stacks, backend instructions, sanitized examples, format/validate CI | `terraform fmt -check` and offline `terraform validate` pass; CI has no apply job. |
| 2. Hierarchy | OU module and existing account placement model | Plan shows only intended OU/account associations; no implicit account creation or management-account move. |
| 3. Policies | SCP/RCP catalog, attachment maps, policy tests | JSON syntax and policy-type constraints pass; test OU rollout and documented exceptions. |
| 4. Identity Center | Four inline-only permission sets and Entra group assignments | No managed policy attachment resources; every assignment resolves a real synchronized group; assignment validation rejects AI-to-human profile mappings and AI access to management/production. Negative tests cover AI role hopping and identity-policy mutation. |
| 5. Portfolio evidence | Architecture diagram, sample redacted plans, operating guide, rollback examples, CI results | Reviewer can trace each guardrail to policy code, tests, scope, limitations, and rollout evidence. |

Each stage gets a small reviewed commit/PR. Apply is a separate authorized operation with a saved plan, peer review, test-OU rollout, observation, and promotion. Never run destroy against the organization or Identity Center stack as a routine cleanup step.

## 10. Risks, limitations, and decisions to confirm before deployment

- **Management account exposure:** SCPs and RCPs do not apply there. Limit direct access and keep break-glass credentials outside this codebase.
- **Policy blast radius:** Root-level SCP/RCP mistakes can block operations across member accounts. Start in a test OU; document exceptions and rollback.
- **AI guardrail coverage:** Explicit denies cover known destructive actions only. A new service action may bypass the list; scope the account and require human plan review.
- **Human credential reuse:** The console, CLI, and SDK can use credentials from a human permission set. If an AI process gains those credentials, AWS cannot reliably identify it as an AI caller. Isolate agent execution and audit credential exposure; do not rely on user-agent strings.
- **Inline policy quota:** Each set has one inline policy with AWS size limits, so a broad read-only policy may require a curated action list or a narrower profile.
- **RCP coverage:** Only supported resource types participate; cross-account service integrations need testing.
- **Identity lifecycle:** Entra/SCIM must exist and sync groups before Terraform assignment; changing group IDs can force assignment replacement.
- **Bootstrap and state:** Remote state and organization creation cannot depend circularly on the same stack. Protect S3 state with encryption, versioning, access control, and tested recovery; keep state out of Git.
- **Costs:** Organizations, SCPs, RCPs, and permission sets are governance constructs, but supporting services (CloudTrail, Config, S3 state, logging, account workloads) can incur charges. Confirm current pricing before deployment.
- **Open deployment inputs:** Actual account inventory, OU ownership, approved regions, Entra group identifiers, Identity Center home region, break-glass process, and policy exceptions remain private inputs to confirm before an apply.

## References

- [AWS Organizations: SCPs and RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_authorization_policies.html)
- [AWS Organizations: RCP effects and limitations](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html)
- [AWS Organizations: management account best practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
- [IAM Identity Center: Microsoft Entra SAML and SCIM](https://docs.aws.amazon.com/singlesignon/latest/userguide/idp-microsoft-entra.html)
- [IAM Identity Center: permission-set quotas](https://docs.aws.amazon.com/singlesignon/latest/userguide/limits.html)
- [IAM Identity Center: credentials for CLI and SDKs](https://docs.aws.amazon.com/singlesignon/latest/userguide/howtogetcredentials.html)
- [IAM global condition keys: `aws:UserAgent` warning](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
- [Terraform AWS provider: Organizations policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy)
- [Terraform AWS provider: permission-set inline policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set_inline_policy)
