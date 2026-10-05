#!/bin/sh
# Applies the repository's GitHub settings with the GitHub CLI (gh), signed in
# as an owner. Safe to run again: every call sets state rather than adding it.
#
#   sh scripts/configure-github.sh            # apply
#   sh scripts/configure-github.sh --show     # print current state only
set -eu

repo="cdf-eagles/aws-cybris-net"

show() {
  gh api "repos/$repo" --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge, allow_update_branch, has_wiki, has_projects, security_and_analysis}'
  gh api "repos/$repo/rulesets" --jq '.[] | {id, name, enforcement}'
  gh api "repos/$repo/actions/permissions/workflow"
  gh api "repos/$repo/actions/permissions/selected-actions" 2>/dev/null || true
  gh api "repos/$repo/vulnerability-alerts" >/dev/null 2>&1 && echo "dependabot alerts: enabled" || echo "dependabot alerts: disabled"
}

if [ "${1:-}" = "--show" ]; then
  show
  exit 0
fi

# Merge methods: squash only, delete the branch on merge, offer "update branch".
gh api -X PATCH "repos/$repo" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F allow_update_branch=true \
  -F has_wiki=false \
  -F has_projects=false \
  -f squash_merge_commit_title=COMMIT_OR_PR_TITLE \
  -f squash_merge_commit_message=COMMIT_MESSAGES >/dev/null
echo "repository: merge methods and features set"

# Secret scanning with push protection (free on a public repository).
gh api -X PATCH "repos/$repo" --input - >/dev/null <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON
echo "repository: secret scanning and push protection enabled"

# Dependabot alerts, Dependabot security updates, private vulnerability reporting.
gh api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null
gh api -X PUT "repos/$repo/automated-security-fixes" >/dev/null
gh api -X PUT "repos/$repo/private-vulnerability-reporting" >/dev/null
echo "repository: Dependabot alerts, security updates, and private vulnerability reporting enabled"

# Actions: only GitHub's own actions and the two pinned third-party ones; the
# default token is read-only and cannot approve pull requests.
gh api -X PUT "repos/$repo/actions/permissions" --input - >/dev/null <<'JSON'
{"enabled":true,"allowed_actions":"selected"}
JSON
gh api -X PUT "repos/$repo/actions/permissions/selected-actions" --input - >/dev/null <<'JSON'
{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["opentofu/setup-opentofu@*","terraform-linters/setup-tflint@*"]}
JSON
gh api -X PUT "repos/$repo/actions/permissions/workflow" --input - >/dev/null <<'JSON'
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}
JSON
echo "actions: allowed actions limited, default token read-only"

# Ruleset on the default branch: pull request required (squash), the Validate
# check required, signed commits, linear history, no force-push, no deletion.
ruleset='{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {"type": "required_signatures"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true,
      "allowed_merge_methods": ["squash"]
    }},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "do_not_enforce_on_create": false,
      "required_status_checks": [{"context": "validate"}]
    }}
  ]
}'
existing=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id')
if [ -n "$existing" ]; then
  printf '%s' "$ruleset" | gh api -X PUT "repos/$repo/rulesets/$existing" --input - >/dev/null
  echo "ruleset main: updated (id $existing)"
else
  printf '%s' "$ruleset" | gh api -X POST "repos/$repo/rulesets" --input - >/dev/null
  echo "ruleset main: created"
fi

echo
show
