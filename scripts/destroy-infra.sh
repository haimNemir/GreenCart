#!/usr/bin/env bash

set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="$ROOT_DIR/bootstrap"
TERRAFORM_DIR="$ROOT_DIR/terraform"

AWS_REGION="us-east-1"
LOG_FILE="/tmp/greencart-destroy-infra-$(date +%Y%m%d-%H%M%S).log"

declare -a SUMMARY_LINES=()

usage() {
  cat <<'EOF'
Usage: scripts/destroy-infra.sh [options]

Options:
  --help   Show this message

This script tears down the full GreenCart infrastructure, including the Terraform
state backend (S3 + DynamoDB). After it completes, the AWS account is in the same
state as before build-infra.sh was run, and the full provisioning flow can be
repeated cleanly by running build-infra.sh again.
EOF
}

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$message" | tee -a "$LOG_FILE"
}

record_summary() {
  SUMMARY_LINES+=("$1")
  log "$1"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Required command not found: $cmd"
    exit 1
  fi
}

run_cmd() {
  local description="$1"
  shift
  local rc=0

  log "RUN: $description"
  "$@" >>"$LOG_FILE" 2>&1
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    record_summary "OK: $description"
    return 0
  fi

  record_summary "ERROR: $description (exit $rc)"
  return "$rc"
}

terraform_destroy() {
  local dir="$1"
  local label="$2"
  shift 2

  run_cmd "Terraform init in $label" terraform -chdir="$dir" init -reconfigure || return 1
  run_cmd "Terraform destroy in $label" terraform -chdir="$dir" destroy -auto-approve -lock-timeout=5m "$@"
}

# If the bootstrap state is empty but a backup with tracked resources exists, restore it.
# This happens when terraform destroy was run directly on the bootstrap directory in the
# past (outside of this script), which emptied the state while the AWS resources survived.
restore_bootstrap_state_if_empty() {
  local state_file="$BOOTSTRAP_DIR/terraform.tfstate"
  local backup_file="$BOOTSTRAP_DIR/terraform.tfstate.backup"

  if [[ -f "$state_file" ]] && ! grep -q '"type":' "$state_file" 2>/dev/null; then
    log "WARNING: Bootstrap state is empty — no resources are tracked."
    if [[ -f "$backup_file" ]] && grep -q '"type":' "$backup_file" 2>/dev/null; then
      log "Restoring bootstrap state from backup so Terraform can destroy the S3 bucket and DynamoDB table."
      cp "$backup_file" "$state_file"
      record_summary "OK: Restored bootstrap state from backup"
    else
      log "WARNING: No usable backup found. S3 bucket and DynamoDB table may be orphaned in AWS after this run."
    fi
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  mkdir -p "$(dirname "$LOG_FILE")"
  : >"$LOG_FILE"

  require_command terraform
  require_command aws

  log "Destroy started. Log file: $LOG_FILE"

  run_cmd "Validate AWS credentials" aws sts get-caller-identity --region "$AWS_REGION" || exit 1

  # Fail fast if the S3 backend is gone — this means the bootstrap was destroyed before
  # the main infra, taking the Terraform state with it. Continuing would silently skip
  # all EC2/VPC/ALB resources and leave them as orphans in AWS.
  local tfstate_bucket
  tfstate_bucket=$(grep 'bucket' "$TERRAFORM_DIR/backend.tf" | head -1 | awk -F'"' '{print $2}')
  if ! aws s3api head-bucket --bucket "$tfstate_bucket" --region "$AWS_REGION" >/dev/null 2>&1; then
    log "ERROR: S3 backend bucket '$tfstate_bucket' does not exist."
    log "The bootstrap was likely destroyed before the main infrastructure."
    log "Terraform state is lost. Any surviving AWS resources must be cleaned up manually,"
    log "then run build-infra.sh to start fresh."
    exit 1
  fi

  # Step 1: Destroy the main infrastructure first, while the Terraform state is still
  # readable from S3. The order is critical — if we destroy the bootstrap first,
  # Terraform loses the state and cannot know what resources to destroy.
  # public_key is required by Terraform but its value is irrelevant for destroy —
  # Terraform reads the existing key pair from state and deletes it without using the variable.
  terraform_destroy "$TERRAFORM_DIR" "terraform" -var="public_key=placeholder" || exit 1

  # Step 2: Destroy the state backend. The S3 bucket is configured with force_destroy = true,
  # so Terraform will empty the bucket (including the state file) before deleting it.
  restore_bootstrap_state_if_empty
  terraform_destroy "$BOOTSTRAP_DIR" "bootstrap" || exit 1

  log "Destroy finished successfully."
  log "The AWS account is back to its initial state. Run build-infra.sh to provision from scratch."

  printf '\nSummary:\n'
  printf '%s\n' "${SUMMARY_LINES[@]}"
}

main "$@"
