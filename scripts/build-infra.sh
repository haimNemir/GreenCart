#!/usr/bin/env bash

set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="$ROOT_DIR/bootstrap"
TERRAFORM_DIR="$ROOT_DIR/terraform"

AWS_REGION="us-east-1"
GITHUB_REPO="haimNemir/GreenCart"
SSH_KEY_PATH="$HOME/.ssh/greencart-key"
LOG_FILE="/tmp/greencart-build-infra-$(date +%Y%m%d-%H%M%S).log"

declare -a SUMMARY_LINES=()

usage() {
  cat <<'EOF'
Usage: scripts/build-infra.sh [options]

Options:
  --ssh-key <path>      Path to the SSH private key file. Default: ~/.ssh/greencart-key
  --repo <owner/repo>   GitHub repository for setting secrets. Default: haimNemir/GreenCart
  --help                Show this message

Prerequisites (run once before the first execution):
  ssh-keygen -t ed25519 -f ~/.ssh/greencart-key
  gh auth login
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

terraform_apply() {
  local dir="$1"
  local label="$2"
  shift 2

  run_cmd "Terraform init in $label" terraform -chdir="$dir" init -reconfigure || return 1
  run_cmd "Terraform apply in $label" terraform -chdir="$dir" apply -auto-approve -lock-timeout=5m "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssh-key)
        SSH_KEY_PATH="$2"
        shift 2
        ;;
      --repo)
        GITHUB_REPO="$2"
        shift 2
        ;;
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
  require_command gh

  log "Build started. Log file: $LOG_FILE"

  run_cmd "Validate AWS credentials" aws sts get-caller-identity --region "$AWS_REGION" || exit 1

  # Step 1: Provision the state backend (S3 bucket + DynamoDB table).
  terraform_apply "$BOOTSTRAP_DIR" "bootstrap" || exit 1

  # Step 2: Read the SSH public key.
  if [[ ! -f "${SSH_KEY_PATH}.pub" ]]; then
    log "SSH public key not found at ${SSH_KEY_PATH}.pub"
    log "Run: ssh-keygen -t ed25519 -f $SSH_KEY_PATH"
    exit 1
  fi
  local public_key
  public_key="$(cat "${SSH_KEY_PATH}.pub")"

  # Step 3: Provision all main infrastructure.
  terraform_apply "$TERRAFORM_DIR" "terraform" \
    -var="public_key=${public_key}" || exit 1

  # Step 4: Read Terraform outputs.
  local ip1 ip2 mongo_private_ip alb_dns role_arn
  ip1="$(terraform -chdir="$TERRAFORM_DIR" output -raw app_instance_1_ip)"
  ip2="$(terraform -chdir="$TERRAFORM_DIR" output -raw app_instance_2_ip)"
  mongo_private_ip="$(terraform -chdir="$TERRAFORM_DIR" output -raw mongo_private_ip)"
  alb_dns="$(terraform -chdir="$TERRAFORM_DIR" output -raw alb_dns_name)"
  role_arn="$(terraform -chdir="$TERRAFORM_DIR" output -raw github_actions_role_arn)"

  record_summary "OK: App instance 1 Elastic IP: $ip1"
  record_summary "OK: App instance 2 Elastic IP: $ip2"
  record_summary "OK: MongoDB private IP: $mongo_private_ip"
  record_summary "OK: ALB DNS name: $alb_dns"
  record_summary "OK: GitHub Actions IAM role ARN: $role_arn"

  # Step 5: Set GitHub Actions secrets so the CI/CD pipeline can deploy.
  run_cmd "Set EC2_APP_IP_1 secret" \
    gh secret set EC2_APP_IP_1 --repo "$GITHUB_REPO" --body "$ip1" || exit 1
  run_cmd "Set EC2_APP_IP_2 secret" \
    gh secret set EC2_APP_IP_2 --repo "$GITHUB_REPO" --body "$ip2" || exit 1
  run_cmd "Set MONGO_URL secret" \
    gh secret set MONGO_URL --repo "$GITHUB_REPO" --body "mongodb://${mongo_private_ip}:27017" || exit 1
  run_cmd "Set EC2_SSH_PRIVATE_KEY secret" \
    gh secret set EC2_SSH_PRIVATE_KEY --repo "$GITHUB_REPO" < "$SSH_KEY_PATH" || exit 1
  run_cmd "Set AWS_ROLE_ARN secret" \
    gh secret set AWS_ROLE_ARN --repo "$GITHUB_REPO" --body "$role_arn" || exit 1

  # Step 6: Wait for the app EC2 instances to pass status checks before triggering CI.
  # user_data installs Docker on first boot — the deploy SSH step will fail if it runs
  # before Docker is ready on the instance.
  local instance_ids
  instance_ids=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters \
      "Name=tag:Project,Values=greencart" \
      "Name=tag:Name,Values=greencart-app-*" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

  run_cmd "Wait for app instances to pass EC2 status checks" \
    aws ec2 wait instance-status-ok \
      --region "$AWS_REGION" \
      --instance-ids $instance_ids || exit 1

  # Step 7: Trigger the CI/CD workflow to build images and deploy the application.
  run_cmd "Trigger CI/CD workflow" \
    gh workflow run ci.yml --repo "$GITHUB_REPO" --ref main || exit 1

  sleep 5

  local run_id
  run_id=$(gh run list --repo "$GITHUB_REPO" --workflow ci.yml \
    --limit 1 --json databaseId --jq '.[0].databaseId')

  if [[ -z "$run_id" ]]; then
    log "ERROR: Could not find the triggered workflow run"
    exit 1
  fi

  log "CI/CD run $run_id started. Waiting for deployment to complete (this takes several minutes)..."
  if gh run watch "$run_id" --repo "$GITHUB_REPO" --exit-status 2>&1 | tee -a "$LOG_FILE"; then
    record_summary "OK: CI/CD deployment completed"
  else
    record_summary "ERROR: CI/CD deployment failed — run: gh run view $run_id --repo $GITHUB_REPO --log-failed"
    exit 1
  fi

  log "Build finished successfully. Application is live at: http://${alb_dns}"

  printf '\nSummary:\n'
  printf '%s\n' "${SUMMARY_LINES[@]}"
}

main "$@"
