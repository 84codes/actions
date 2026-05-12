#!/bin/bash
# Update CloudFront Response Headers Policy with CSP from csp-policy.json
#
# Usage: ./update-cloudfront-csp.sh <policy-id-or-name> [options]
#
# Arguments:
#   policy-id-or-name          Either a policy ID (UUID) or policy name to find/create
#
# Options:
#   --create-if-missing        Create the policy if it doesn't exist (requires name, not ID)
#   --attach-to <dist-id>      Attach the policy to this CloudFront distribution
#
# Environment:
#   CSP_POLICY_FILE            Path to csp-policy.json (default: csp-policy.json)
#
# Examples:
#   ./update-cloudfront-csp.sh my-csp-policy --create-if-missing --attach-to EXAMPLEDIST12345

set -euo pipefail

POLICY_ID_OR_NAME="$1"
CREATE_IF_MISSING=""
ATTACH_TO_DISTRIBUTION=""

if [ -z "$POLICY_ID_OR_NAME" ]; then
  echo "Usage: $0 <policy-id-or-name> [--create-if-missing] [--attach-to <dist-id>]" >&2
  exit 1
fi

shift
while [[ $# -gt 0 ]]; do
  case $1 in
    --create-if-missing)
      CREATE_IF_MISSING="true"
      shift
      ;;
    --attach-to)
      ATTACH_TO_DISTRIBUTION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

CSP_POLICY_FILE="${CSP_POLICY_FILE:-csp-policy.json}"

if [ ! -f "$CSP_POLICY_FILE" ]; then
  echo "CSP policy file not found: $CSP_POLICY_FILE" >&2
  exit 1
fi

# Build CSP string from JSON directives
echo "Building CSP from $CSP_POLICY_FILE..."
CSP_STRING=""
for directive in $(jq -r '.directives | keys[]' "$CSP_POLICY_FILE"); do
  values=$(jq -r ".directives.\"$directive\" | join(\" \")" "$CSP_POLICY_FILE")
  if [ -z "$values" ]; then
    CSP_STRING="${CSP_STRING}${directive}; "
  else
    CSP_STRING="${CSP_STRING}${directive} ${values}; "
  fi
done
CSP_STRING="${CSP_STRING% }"
echo "CSP: $CSP_STRING"

# Determine if we have an ID or a name
POLICY_CREATED=""
if [[ "$POLICY_ID_OR_NAME" =~ ^[0-9a-f-]{36}$ ]]; then
  POLICY_ID="$POLICY_ID_OR_NAME"
  echo "Using policy ID: $POLICY_ID"
else
  POLICY_NAME="$POLICY_ID_OR_NAME"
  echo "Looking up policy by name: $POLICY_NAME"
  POLICY_ID=$(aws cloudfront list-response-headers-policies \
    --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='${POLICY_NAME}'].ResponseHeadersPolicy.Id | [0]" \
    --output text 2>/dev/null || echo "None")

  if [ -z "$POLICY_ID" ] || [ "$POLICY_ID" = "None" ]; then
    if [ -n "$CREATE_IF_MISSING" ]; then
      echo "Policy not found, creating: $POLICY_NAME"

      POLICY_CONFIG=$(cat <<EOF
{
  "Name": "${POLICY_NAME}",
  "Comment": "CSP policy managed by GitHub Actions",
  "SecurityHeadersConfig": {
    "ContentSecurityPolicy": {
      "Override": true,
      "ContentSecurityPolicy": "${CSP_STRING}"
    }
  }
}
EOF
)
      RESULT=$(aws cloudfront create-response-headers-policy \
        --response-headers-policy-config "$POLICY_CONFIG" \
        --output json)
      POLICY_ID=$(echo "$RESULT" | jq -r '.ResponseHeadersPolicy.Id')
      echo "Created policy: $POLICY_ID"
      POLICY_CREATED="true"
    else
      echo "Policy not found: $POLICY_NAME" >&2
      echo "Use --create-if-missing to create it" >&2
      exit 1
    fi
  else
    echo "Found policy ID: $POLICY_ID"
  fi
fi

# Skip update if we just created the policy
if [ -z "$POLICY_CREATED" ]; then

echo "Fetching current policy configuration..."
aws cloudfront get-response-headers-policy \
  --id "$POLICY_ID" \
  --output json > /tmp/current-policy.json

ETAG=$(jq -r '.ETag' /tmp/current-policy.json)
echo "Current ETag: $ETAG"

echo "Updating CSP in policy configuration..."
jq --arg csp "$CSP_STRING" \
  '.ResponseHeadersPolicy.ResponseHeadersPolicyConfig.SecurityHeadersConfig.ContentSecurityPolicy.ContentSecurityPolicy = $csp' \
  /tmp/current-policy.json > /tmp/updated-policy.json

# Extract config and remove incomplete security header sections
# AWS requires all mandatory fields when these sections exist
jq '.ResponseHeadersPolicy.ResponseHeadersPolicyConfig |
  if .SecurityHeadersConfig.XSSProtection and
     (.SecurityHeadersConfig.XSSProtection.Override == null or
      .SecurityHeadersConfig.XSSProtection.Protection == null)
  then del(.SecurityHeadersConfig.XSSProtection)
  else . end |
  if .SecurityHeadersConfig.FrameOptions and
     (.SecurityHeadersConfig.FrameOptions.Override == null or
      .SecurityHeadersConfig.FrameOptions.FrameOption == null)
  then del(.SecurityHeadersConfig.FrameOptions)
  else . end |
  if .SecurityHeadersConfig.ReferrerPolicy and
     (.SecurityHeadersConfig.ReferrerPolicy.Override == null or
      .SecurityHeadersConfig.ReferrerPolicy.ReferrerPolicy == null)
  then del(.SecurityHeadersConfig.ReferrerPolicy)
  else . end |
  if .SecurityHeadersConfig.ContentTypeOptions and
     (.SecurityHeadersConfig.ContentTypeOptions.Override == null)
  then del(.SecurityHeadersConfig.ContentTypeOptions)
  else . end |
  if .SecurityHeadersConfig.StrictTransportSecurity and
     (.SecurityHeadersConfig.StrictTransportSecurity.Override == null or
      .SecurityHeadersConfig.StrictTransportSecurity.AccessControlMaxAgeSec == null)
  then del(.SecurityHeadersConfig.StrictTransportSecurity)
  else . end' \
  /tmp/updated-policy.json > /tmp/policy-config.json

echo "Updating CloudFront Response Headers Policy..."
aws cloudfront update-response-headers-policy \
  --id "$POLICY_ID" \
  --if-match "$ETAG" \
  --response-headers-policy-config file:///tmp/policy-config.json \
  --output json > /tmp/update-result.json

NEW_ETAG=$(jq -r '.ETag' /tmp/update-result.json)
echo "Policy updated. New ETag: $NEW_ETAG"

rm -f /tmp/current-policy.json /tmp/updated-policy.json /tmp/policy-config.json /tmp/update-result.json

fi

# Attach policy to distribution if requested
if [ -n "$ATTACH_TO_DISTRIBUTION" ]; then
  echo "Checking if policy needs to be attached to distribution $ATTACH_TO_DISTRIBUTION..."

  DIST_CONFIG=$(aws cloudfront get-distribution-config --id "$ATTACH_TO_DISTRIBUTION" --output json)
  CURRENT_POLICY=$(echo "$DIST_CONFIG" | jq -r '.DistributionConfig.DefaultCacheBehavior.ResponseHeadersPolicyId // empty')

  if [ "$CURRENT_POLICY" != "$POLICY_ID" ]; then
    echo "Attaching policy to distribution..."
    DIST_ETAG=$(echo "$DIST_CONFIG" | jq -r '.ETag')
    echo "$DIST_CONFIG" | jq --arg pid "$POLICY_ID" \
      '.DistributionConfig.DefaultCacheBehavior.ResponseHeadersPolicyId = $pid | .DistributionConfig' \
      > /tmp/dist-config.json

    aws cloudfront update-distribution \
      --id "$ATTACH_TO_DISTRIBUTION" \
      --if-match "$DIST_ETAG" \
      --distribution-config file:///tmp/dist-config.json \
      --output json > /dev/null

    rm -f /tmp/dist-config.json
    echo "Policy attached to distribution"
  else
    echo "Policy already attached to distribution"
  fi
fi
