#!/usr/bin/env bash
# Opens a `pipeline-failure` issue for a failed daily pipeline run, or comments on the one already open, so repeated
# failures land in one thread. Needs GH_TOKEN, RUN_URL and GITHUB_REPOSITORY (the workflow sets them).
set -euo pipefail

label=pipeline-failure
gh label create "$label" --repo "$GITHUB_REPOSITORY" --color B60205 \
  --description "The daily article pipeline failed" 2>/dev/null || true
open=$(gh issue list --repo "$GITHUB_REPOSITORY" --label "$label" --state open --json number --jq '.[0].number // empty')
if [ -n "$open" ]; then
  gh issue comment "$open" --repo "$GITHUB_REPOSITORY" --body "Failed again: $RUN_URL"
else
  gh issue create --repo "$GITHUB_REPOSITORY" --label "$label" --title "Daily pipeline failed" \
    --body "The daily article pipeline failed: $RUN_URL. Its log says why; this issue collects any repeat failures."
fi
