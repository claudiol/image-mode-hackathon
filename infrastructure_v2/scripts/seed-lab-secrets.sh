#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_PROFILE="${AWS_PROFILE:-}"
SECRET_PREFIX="${SECRET_PREFIX:-image-mode-lab}"
DELETE_MODE=false
CREATE_MISSING=false

usage() {
  cat <<EOF
Usage:
  $0 [--profile AWS_PROFILE] [--region AWS_REGION] [--prefix SECRET_PREFIX] [--create-missing] [--delete]

Examples:
  $0 --profile image-mode-lab --region us-east-2 --prefix image-mode-lab
  $0 --profile image-mode-lab --region us-east-2 --prefix image-mode-lab --create-missing
  $0 --profile image-mode-lab --region us-east-2 --prefix image-mode-lab --delete
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      AWS_PROFILE="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --prefix)
      SECRET_PREFIX="$2"
      shift 2
      ;;
    --create-missing)
      CREATE_MISSING=true
      shift
      ;;
    --delete)
      DELETE_MODE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

AWS_ARGS=(--region "$AWS_REGION")

if [[ -n "$AWS_PROFILE" ]]; then
  AWS_ARGS+=(--profile "$AWS_PROFILE")
fi

SECRET_NAMES=(
  "aap/postgresql_admin_password"
  "aap/gateway_admin_username"
  "aap/gateway_admin_password"
  "aap/gateway_pg_password"
  "aap/controller_admin_password"
  "aap/controller_pg_password"
  "aap/hub_admin_password"
  "aap/hub_pg_password"
  "aap/eda_admin_password"
  "aap/eda_pg_password"
  "aap/automationmetrics_pg_password"
  "aap/automationmetrics_controller_read_pg_password"
  "aap/vault_password"

  "idm/admin_password"
  "idm/directory_manager_password"
  "idm/kerberos_master_password"

  "satellite/admin_password"

  "quay/db_password"
  "quay/secret_key"
  "quay/superuser"
  "quay/superuser_password"
  "quay/admin_access_token"

  "redhat/org_id"
  "redhat/aap_activation_key"
  "redhat/registry_username"
  "redhat/registry_password"

  "git/username"
  "git/token"

  "ssh/aws_ssh_private_key"
  "ssh/image_mode_ssh_private_key"
)

random_secret() {
  openssl rand -base64 32
}

prompt_secret() {
  local label="$1"
  local value
  read -r -s -p "$label: " value
  echo
  printf '%s' "$value"
}

prompt_value() {
  local label="$1"
  local value
  read -r -p "$label: " value
  printf '%s' "$value"
}

secret_exists() {
  local full_name="$1"

  aws secretsmanager describe-secret \
    "${AWS_ARGS[@]}" \
    --secret-id "$full_name" >/dev/null 2>&1
}

put_secret() {
  local name="$1"
  local value="$2"
  local full_name="${SECRET_PREFIX}/${name}"

  if [[ -z "$value" ]]; then
    echo "Skipping empty value: $full_name"
    return 0
  fi

  if secret_exists "$full_name"; then
    aws secretsmanager put-secret-value \
      "${AWS_ARGS[@]}" \
      --secret-id "$full_name" \
      --secret-string "$value" >/dev/null

    echo "Updated: $full_name"
  else
    if [[ "$CREATE_MISSING" == true ]]; then
      aws secretsmanager create-secret \
        "${AWS_ARGS[@]}" \
        --name "$full_name" \
        --secret-string "$value" >/dev/null

      echo "Created and populated: $full_name"
    else
      echo "Missing, run Terraform first or use --create-missing: $full_name"
      return 1
    fi
  fi
}

delete_secret() {
  local name="$1"
  local full_name="${SECRET_PREFIX}/${name}"

  if secret_exists "$full_name"; then
    aws secretsmanager delete-secret \
      "${AWS_ARGS[@]}" \
      --secret-id "$full_name" \
      --force-delete-without-recovery >/dev/null

    echo "Deleted: $full_name"
  else
    echo "Not found: $full_name"
  fi
}

delete_all_secrets() {
  echo
  echo "Delete mode enabled."
  echo "AWS Region:    $AWS_REGION"
  echo "AWS Profile:   ${AWS_PROFILE:-default}"
  echo "Secret Prefix: $SECRET_PREFIX"
  echo

  read -r -p "Type DELETE to permanently delete these lab secrets: " CONFIRM

  if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Delete cancelled."
    exit 1
  fi

  for name in "${SECRET_NAMES[@]}"; do
    delete_secret "$name"
  done

  echo
  echo "Delete complete."
}

echo
echo "AWS Region:    $AWS_REGION"
echo "AWS Profile:   ${AWS_PROFILE:-default}"
echo "Secret Prefix: $SECRET_PREFIX"
echo

aws sts get-caller-identity "${AWS_ARGS[@]}"

if [[ "$DELETE_MODE" == true ]]; then
  delete_all_secrets
  exit 0
fi

put_secret "aap/postgresql_admin_password" "$(random_secret)"
put_secret "aap/gateway_admin_username" "admin"
put_secret "aap/gateway_admin_password" "$(random_secret)"
put_secret "aap/gateway_pg_password" "$(random_secret)"
put_secret "aap/controller_admin_password" "$(random_secret)"
put_secret "aap/controller_pg_password" "$(random_secret)"
put_secret "aap/hub_admin_password" "$(random_secret)"
put_secret "aap/hub_pg_password" "$(random_secret)"
put_secret "aap/eda_admin_password" "$(random_secret)"
put_secret "aap/eda_pg_password" "$(random_secret)"
put_secret "aap/automationmetrics_pg_password" "$(random_secret)"
put_secret "aap/automationmetrics_controller_read_pg_password" "$(random_secret)"
put_secret "aap/vault_password" "$(random_secret)"

put_secret "idm/admin_password" "$(random_secret)"
put_secret "idm/directory_manager_password" "$(random_secret)"
put_secret "idm/kerberos_master_password" "$(random_secret)"

put_secret "satellite/admin_password" "$(random_secret)"

put_secret "quay/db_password" "$(random_secret)"
put_secret "quay/secret_key" "$(random_secret)"
put_secret "quay/superuser" "quayadmin"
put_secret "quay/superuser_password" "$(random_secret)"
put_secret "quay/admin_access_token" "CHANGE_ME_AFTER_QUAY_DEPLOYMENT"

put_secret "redhat/org_id" "$(prompt_value 'Red Hat org ID')"
put_secret "redhat/aap_activation_key" "$(prompt_value 'AAP activation key')"
put_secret "redhat/registry_username" "$(prompt_value 'registry.redhat.io username')"
put_secret "redhat/registry_password" "$(prompt_secret 'registry.redhat.io password')"

put_secret "git/username" "$(prompt_value 'Git username')"
put_secret "git/token" "$(prompt_secret 'Git token')"

read -r -p "AWS bootstrap private key PEM path: " AWS_KEY_FILE
if [[ -f "$AWS_KEY_FILE" ]]; then
  put_secret "ssh/aws_ssh_private_key" "$(cat "$AWS_KEY_FILE")"
else
  echo "Skipping missing AWS SSH key"
fi

read -r -p "Image Mode SSH private key PEM path: " IMAGE_KEY_FILE
if [[ -f "$IMAGE_KEY_FILE" ]]; then
  put_secret "ssh/image_mode_ssh_private_key" "$(cat "$IMAGE_KEY_FILE")"
else
  echo "Skipping missing Image Mode SSH key"
fi

echo
echo "Completed secret value update."
echo "Region:  $AWS_REGION"
echo "Profile: ${AWS_PROFILE:-default}"
echo "Prefix:  $SECRET_PREFIX/"