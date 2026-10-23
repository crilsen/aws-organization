#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
action="${1:-}"
stack="${2:-}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_var() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required environment variable is missing: ${name}"
}

validate_stack() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    printf 'SKIP: Terraform stack directory is not present: %s\n' "$dir"
    return
  fi
  if ! find "$dir" -maxdepth 1 -name '*.tf' -print -quit | grep -q .; then
    printf 'SKIP: no Terraform root module in %s yet\n' "$dir"
    return
  fi
  terraform -chdir="$dir" init -backend=false -input=false -no-color
  terraform -chdir="$dir" validate -no-color
}

validate_all() {
  terraform fmt -check -recursive "$repo_root"
  validate_stack "$repo_root/stacks/organization"
  validate_stack "$repo_root/stacks/identity-center"
}

require_deployment_context() {
  case "$stack" in
    organization|identity-center) ;;
    *) die 'Stack must be organization or identity-center' ;;
  esac
  [[ -f "$repo_root/stacks/$stack/main.tf" ]] || die "Terraform stack is not implemented: $stack"
  case "${CI_ENGINE:-}" in
    github|gitlab|jenkins) ;;
    *) die 'CI_ENGINE must be github, gitlab, or jenkins' ;;
  esac
  require_var CI_RUN_ID
  require_var CI_COMMIT_SHA
  require_var CI_REF
  require_var TF_PLAN_BUCKET
  require_var TF_PLAN_KMS_KEY
  [[ "$CI_REF" == main ]] || die 'Plan and apply require the protected main branch'
  [[ "$(git -C "$repo_root" rev-parse HEAD)" == "$CI_COMMIT_SHA" ]] || die 'Checked-out commit does not match CI_COMMIT_SHA'
  aws sts get-caller-identity >/dev/null
}

plan_stack() (
  require_deployment_context
  require_var TF_METADATA_FILE
  local dir="$repo_root/stacks/$stack"
  local key="aws-organization/$CI_ENGINE/$CI_RUN_ID/$stack/$CI_COMMIT_SHA.tfplan"
  local temp_dir plan_file plan_text plan_sha
  temp_dir="$(mktemp -d)"
  plan_file="$temp_dir/plan.tfplan"
  plan_text="$temp_dir/plan.txt"
  trap 'rm -f "$plan_file" "$plan_text"; rmdir "$temp_dir"' EXIT

  if ! terraform -chdir="$dir" init -input=false -no-color >/dev/null 2>&1; then
    die 'Terraform init failed. Check the private runner configuration and backend.'
  fi
  if ! terraform -chdir="$dir" plan -input=false -no-color -lock-timeout=5m -out="$plan_file" >"$plan_text" 2>&1; then
    die 'Terraform plan failed. Inspect the private runner log; plan details were not published.'
  fi
  plan_sha="$(sha256sum "$plan_file" | cut -d ' ' -f 1)"
  aws s3 cp "$plan_file" "s3://$TF_PLAN_BUCKET/$key" --sse aws:kms --sse-kms-key-id "$TF_PLAN_KMS_KEY" --only-show-errors >/dev/null
  aws s3 cp "$plan_text" "s3://$TF_PLAN_BUCKET/$key.txt" --sse aws:kms --sse-kms-key-id "$TF_PLAN_KMS_KEY" --only-show-errors >/dev/null
  printf 'TF_PLAN_KEY=%s\nTF_PLAN_SHA256=%s\n' "$key" "$plan_sha" >"$TF_METADATA_FILE"
  printf 'Plan stored privately: s3://%s/%s.txt\nSHA-256: %s\n' "$TF_PLAN_BUCKET" "$key" "$plan_sha"
)

apply_stack() (
  require_deployment_context
  [[ "${CI_APPLY_APPROVED:-}" == yes ]] || die 'Native CI approval is required before apply'
  [[ "${CI_APPLY_GATE_ACK:-}" == configured ]] || die 'Apply gate has not been activated by the platform administrator'
  require_var TF_PLAN_KEY
  require_var TF_PLAN_SHA256
  local expected="aws-organization/$CI_ENGINE/$CI_RUN_ID/$stack/$CI_COMMIT_SHA.tfplan"
  [[ "$TF_PLAN_KEY" == "$expected" ]] || die 'Plan key does not match this CI run, stack, and commit'
  local dir="$repo_root/stacks/$stack"
  local temp_dir plan_file apply_log actual_sha
  temp_dir="$(mktemp -d)"
  plan_file="$temp_dir/plan.tfplan"
  apply_log="$temp_dir/apply.log"
  trap 'rm -f "$plan_file" "$apply_log"; rmdir "$temp_dir"' EXIT

  aws s3 cp "s3://$TF_PLAN_BUCKET/$TF_PLAN_KEY" "$plan_file" --only-show-errors >/dev/null
  actual_sha="$(sha256sum "$plan_file" | cut -d ' ' -f 1)"
  [[ "$actual_sha" == "$TF_PLAN_SHA256" ]] || die 'Downloaded plan checksum does not match the reviewed plan'
  if ! terraform -chdir="$dir" init -input=false -no-color >/dev/null 2>&1; then
    die 'Terraform init failed. Check the private runner configuration and backend.'
  fi
  if terraform -chdir="$dir" apply -input=false -no-color "$plan_file" >"$apply_log" 2>&1; then
    aws s3 cp "$apply_log" "s3://$TF_PLAN_BUCKET/$TF_PLAN_KEY.apply.log" --sse aws:kms --sse-kms-key-id "$TF_PLAN_KMS_KEY" --only-show-errors >/dev/null
    printf 'Apply completed. Private log: s3://%s/%s.apply.log\n' "$TF_PLAN_BUCKET" "$TF_PLAN_KEY"
  else
    aws s3 cp "$apply_log" "s3://$TF_PLAN_BUCKET/$TF_PLAN_KEY.apply.log" --sse aws:kms --sse-kms-key-id "$TF_PLAN_KMS_KEY" --only-show-errors >/dev/null || true
    die 'Terraform apply failed. Inspect the encrypted private log; no resource details were printed publicly.'
  fi
)

case "$action" in
  validate) validate_all ;;
  plan) plan_stack ;;
  apply) apply_stack ;;
  *) die 'Usage: terraform.sh validate | plan <stack> | apply <stack>' ;;
esac
