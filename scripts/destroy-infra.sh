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

  # Step 1: Destroy the main infrastructure first, while the Terraform state is still
  # readable from S3. The order is critical — if we destroy the bootstrap first,
  # Terraform loses the state and cannot know what resources to destroy.
  terraform_destroy "$TERRAFORM_DIR" "terraform" || exit 1

  # Step 2: Destroy the state backend. The S3 bucket is configured with force_destroy = true,
  # so Terraform will empty the bucket (including the state file) before deleting it.
  terraform_destroy "$BOOTSTRAP_DIR" "bootstrap" || exit 1

  log "Destroy finished successfully."
  log "The AWS account is back to its initial state. Run build-infra.sh to provision from scratch."

  printf '\nSummary:\n'
  printf '%s\n' "${SUMMARY_LINES[@]}"
}

main "$@"
