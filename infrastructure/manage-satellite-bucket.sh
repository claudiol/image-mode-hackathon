#!/usr/bin/env bash
#
# manage-satellite-bucket.sh
#
# Manage cross-account access to the Satellite installer S3 bucket and
# upload (deploy) the Satellite ISO to it.
#
#   grant   <account-id> [account-id ...]   Grant an AWS account read+write access
#   revoke  <account-id> [account-id ...]   Remove an AWS account's access
#   upload  <local-file> [s3-key]           Upload (deploy) an ISO to the bucket
#   show                                    Print the current bucket policy + contents
#
# Access is granted via the bucket policy (resource-based), so you pass the
# 12-digit AWS *account ID* you want to trust -- not an individual IAM user.
# The trusted account's own admin still has to allow their IAM principals to
# use this bucket ARN; the bucket policy is only the bucket-owner half.
#
# Config via env or flags:
#   BUCKET       (default: satellite-installer)   --bucket <name>
#   AWS_PROFILE  (optional)                        --profile <name>
#   AWS_REGION   (optional; auto-detected)         --region <name>
#
# Requires: aws CLI v2, jq.
#
set -euo pipefail

BUCKET="${BUCKET:-satellite-installer}"
PROFILE="${AWS_PROFILE:-}"
REGION="${AWS_REGION:-}"
SID="CrossAccountSatelliteInstallerAccess"
DEFAULT_KEY="6.19/Satellite-6.19.1-rhel-9-x86_64.iso"

# Read+write action set. Add "s3:DeleteObject" here if trusted accounts should
# also be able to delete objects.
ACTIONS='["s3:ListBucket","s3:GetBucketLocation","s3:GetObject","s3:PutObject"]'

die() { echo "error: $*" >&2; exit 1; }

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- parse global flags (before the subcommand) ------------------------------
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --bucket)  BUCKET="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *)         ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]:-}"

command -v aws >/dev/null 2>&1 || die "aws CLI not found on PATH."
command -v jq  >/dev/null 2>&1 || die "jq not found on PATH."

# aws profile flag, expanded only when set
aws_cli() {
  if [ -n "$PROFILE" ]; then aws --profile "$PROFILE" "$@"; else aws "$@"; fi
}

validate_account() {
  [[ "$1" =~ ^[0-9]{12}$ ]] || die "invalid AWS account id '$1' (must be 12 digits)."
}

detect_region() {
  [ -n "$REGION" ] && { echo "$REGION"; return; }
  local r
  r="$(aws_cli s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text 2>/dev/null || echo "")"
  # us-east-1 is reported as "None"/null by the API.
  if [ -z "$r" ] || [ "$r" = "None" ] || [ "$r" = "null" ]; then echo "us-east-1"; else echo "$r"; fi
}

get_policy() {
  aws_cli s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text 2>/dev/null \
    || echo '{"Version":"2012-10-17","Statement":[]}'
}

put_policy() {
  aws_cli s3api put-bucket-policy --bucket "$BUCKET" --policy "$1"
}

# Build a JSON array of "arn:aws:iam::<acct>:root" from account-id args.
principals_json() {
  jq -nc '$ARGS.positional | map("arn:aws:iam::\(.):root")' --args "$@"
}

cmd_grant() {
  [ $# -ge 1 ] || usage 1
  for a in "$@"; do validate_account "$a"; done
  local principals; principals="$(principals_json "$@")"

  local policy; policy="$(get_policy)"
  local new
  new="$(jq \
    --arg sid "$SID" \
    --arg bucket_arn "arn:aws:s3:::$BUCKET" \
    --arg objects_arn "arn:aws:s3:::$BUCKET/*" \
    --argjson principals "$principals" \
    --argjson actions "$ACTIONS" '
    # normalize a Principal.AWS field (string|array|absent) to an array
    def as_arr(x): (x // []) | if type=="array" then . else [.] end;
    ( [ .Statement[]? | select(.Sid == $sid) ] | length ) as $has
    | if $has > 0 then
        .Statement |= map(
          if .Sid == $sid
          then .Principal.AWS = (as_arr(.Principal.AWS) + $principals | unique)
          else . end)
      else
        .Statement += [{
          Sid: $sid,
          Effect: "Allow",
          Principal: { AWS: ($principals | unique) },
          Action: $actions,
          Resource: [$bucket_arn, $objects_arn]
        }]
      end
    ' <<<"$policy")"

  put_policy "$new"
  echo "Granted read+write on s3://$BUCKET to: $*"
  echo "Reminder: each trusted account must also allow its own IAM principals to use $BUCKET."
}

cmd_revoke() {
  [ $# -ge 1 ] || usage 1
  for a in "$@"; do validate_account "$a"; done
  local principals; principals="$(principals_json "$@")"

  local policy; policy="$(get_policy)"
  local new
  new="$(jq \
    --arg sid "$SID" \
    --argjson principals "$principals" '
    def as_arr(x): (x // []) | if type=="array" then . else [.] end;
    .Statement |= (
      map(
        if .Sid == $sid
        then .Principal.AWS = (as_arr(.Principal.AWS) - $principals)
        else . end)
      # drop our statement entirely if no principals remain
      | map(select(.Sid != $sid or ((.Principal.AWS // []) | length) > 0))
    )
    ' <<<"$policy")"

  # If no statements remain, delete the policy rather than leaving an empty one.
  if [ "$(jq '.Statement | length' <<<"$new")" -eq 0 ]; then
    aws_cli s3api delete-bucket-policy --bucket "$BUCKET"
    echo "Revoked access for: $*  (bucket policy now empty and removed)"
  else
    put_policy "$new"
    echo "Revoked access for: $*"
  fi
}

cmd_upload() {
  [ $# -ge 1 ] || usage 1
  local file="$1"; local key="${2:-$DEFAULT_KEY}"
  [ -f "$file" ] || die "file not found: $file"
  local region; region="$(detect_region)"
  echo "Uploading $file -> s3://$BUCKET/$key (region: $region) ..."
  aws_cli s3 cp "$file" "s3://$BUCKET/$key" --region "$region"
  echo "Done: s3://$BUCKET/$key"
}

cmd_show() {
  echo "== Bucket policy for s3://$BUCKET =="
  get_policy | jq .
  echo
  echo "== Objects =="
  aws_cli s3 ls "s3://$BUCKET" --recursive || true
}

# --- dispatch ----------------------------------------------------------------
SUBCMD="${1:-}"; [ $# -gt 0 ] && shift || true
case "$SUBCMD" in
  grant)  cmd_grant  "$@" ;;
  revoke) cmd_revoke "$@" ;;
  upload) cmd_upload "$@" ;;
  show)   cmd_show   "$@" ;;
  ""|-h|--help) usage 0 ;;
  *)      die "unknown command '$SUBCMD' (try: grant, revoke, upload, show)" ;;
esac
