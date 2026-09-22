#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "$REDIRECTS_FILE" ]; then
  echo "No $REDIRECTS_FILE, skipping redirects"
  exit 0
fi

count=$(jq -r 'length' "$REDIRECTS_FILE")
echo "Applying $count redirects to $BUCKET"
if [ "$count" -eq 0 ]; then
  exit 0
fi

# Each upload starts an AWS CLI process. Overlap up to eight uploads to avoid
# paying the startup and request latency sequentially for every redirect.
# NUL delimiters preserve spaces, quotes, and shell metacharacters in URLs.
# xargs returns a nonzero status if any upload fails.
# Expand arguments in the child shell, not while constructing its command.
# shellcheck disable=SC2016
jq -j 'to_entries[] | .key, "\u0000", .value, "\u0000"' "$REDIRECTS_FILE" |
  xargs -0 -n 2 -P 8 bash -c '
    echo "Redirecting $1 -> $2"
    aws s3api put-object \
      --bucket "$BUCKET" \
      --key "$1" \
      --website-redirect-location "$2" \
      --content-type "text/html;charset=utf-8" >/dev/null
  ' _
