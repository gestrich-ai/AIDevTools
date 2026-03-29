#!/bin/bash
set -euo pipefail

PR_NUMBER="${1:?Usage: $0 <pr_number> [mode]}"
MODE="${2:-all}"

BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName')

echo "Running PR Radar on PR #$PR_NUMBER (branch: $BRANCH, mode: $MODE)"
gh workflow run "PR Radar" --ref "$BRANCH" -f pr_number="$PR_NUMBER" -f mode="$MODE"
