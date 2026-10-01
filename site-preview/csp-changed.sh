#!/bin/bash
# Print "true" when the CSP policy file differs from the copy on the pull
# request's base branch, otherwise "false".
#
# Usage: ./csp-changed.sh <repo> <pr-number> <csp-policy-file>
#
# Comparing contents works for pull requests of any size. Listing the changed
# files does not: `gh pr view --json files` returns at most 100 of them.

set -euo pipefail

REPO="$1"
PR_NUMBER="$2"
CSP_POLICY_FILE="$3"

if [ ! -f "$CSP_POLICY_FILE" ]; then
  echo false
  exit 0
fi

BASE_SHA=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json baseRefOid --jq .baseRefOid)

# A policy file missing on the base branch fails the request: the PR adds it.
if gh api --header "Accept: application/vnd.github.raw+json" \
    "repos/$REPO/contents/$CSP_POLICY_FILE?ref=$BASE_SHA" 2>/dev/null \
    | cmp -s - "$CSP_POLICY_FILE"; then
  echo false
else
  echo true
fi
