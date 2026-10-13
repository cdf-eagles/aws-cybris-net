#!/bin/sh
# Applies the standard GitHub settings to one public repository with the
# GitHub CLI (gh), signed in as an owner. Safe to run again: every call sets
# state rather than adding it. Per-repository values (allowed third-party
# actions, required checks, deploy-key bypass) are read from
# scripts/github-settings/<repository>.conf.
#
#   sh scripts/configure-github.sh aws-cybris-net            # apply
#   sh scripts/configure-github.sh aws-cybris-net --show     # print current state only
set -eu
set -f

owner="cdf-eagles"
name="${1:-}"
mode="${2:-apply}"
case "$0" in /*) self="$0" ;; *) self="$PWD/$0" ;; esac
here=$(dirname "$self")
conf="$here/github-settings/$name.conf"

if [ -z "$name" ] || [ ! -f "$conf" ]; then
  echo "usage: sh scripts/configure-github.sh <repository> [--show]" >&2
  printf 'repositories:' >&2
  set +f
  for f in "$here"/github-settings/*.conf; do printf ' %s' "$(basename "$f" .conf)" >&2; done
  echo >&2
  exit 2
fi
case "$mode" in apply|--show) ;; *) echo "unknown option: $mode" >&2; exit 2 ;; esac

allowed_actions=""
required_checks=""
bypass_deploy_keys="false"
# shellcheck source=/dev/null
. "$conf"
repo="$owner/$name"

# Auth preflight: stop before any other call if gh cannot act as an admin.
if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not signed in; run: gh auth login" >&2
  exit 1
fi
admin=$(gh api "repos/$repo" --jq '.permissions.admin') || { echo "cannot read $repo" >&2; exit 1; }
if [ "$admin" != "true" ]; then
  echo "gh is signed in without admin rights on $repo" >&2
  exit 1
fi

# Prints words as a JSON array of strings.
json_array() {
  out=""
  for w in "$@"; do
    out="$out${out:+,}\"$w\""
  done
  printf '[%s]' "$out"
}

show() {
  echo "== $repo"
  gh api "repos/$repo" --jq '{visibility, allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge, allow_update_branch, has_wiki, has_projects, security_and_analysis}'
  gh api "repos/$repo/rulesets" --jq '.[] | {id, name, enforcement}'
  for id in $(gh api "repos/$repo/rulesets" --jq '.[].id'); do
    gh api "repos/$repo/rulesets/$id" --jq '{name, bypass_actors, rules: [.rules[] | .type], required_checks: [.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]}'
  done
  gh api "repos/$repo/actions/permissions"
  gh api "repos/$repo/actions/permissions/workflow"
  gh api "repos/$repo/actions/permissions/selected-actions" 2>/dev/null || echo "selected actions: not set"
  gh api "repos/$repo/vulnerability-alerts" >/dev/null 2>&1 && echo "dependabot alerts: enabled" || echo "dependabot alerts: disabled"
  gh api "repos/$repo/automated-security-fixes" --jq '"dependabot security updates: \(.enabled)"' 2>/dev/null || echo "dependabot security updates: unknown"
  gh api "repos/$repo/private-vulnerability-reporting" --jq '"private vulnerability reporting: \(.enabled)"' 2>/dev/null || echo "private vulnerability reporting: unknown"
}

if [ "$mode" = "--show" ]; then
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

# Actions: only GitHub's own actions and the repository's listed third-party
# ones; the default token is read-only and cannot approve pull requests.
# shellcheck disable=SC2086
patterns=$(json_array $allowed_actions)
gh api -X PUT "repos/$repo/actions/permissions" --input - >/dev/null <<'JSON'
{"enabled":true,"allowed_actions":"selected"}
JSON
printf '{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":%s}' "$patterns" |
  gh api -X PUT "repos/$repo/actions/permissions/selected-actions" --input - >/dev/null
gh api -X PUT "repos/$repo/actions/permissions/workflow" --input - >/dev/null <<'JSON'
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}
JSON
echo "actions: allowed actions limited to GitHub's own plus $patterns, default token read-only"

# Ruleset on the default branch: pull request required (squash), the listed
# checks required, signed commits, linear history, no force-push, no deletion.
# Rule types this script does not manage, and bypass actors other than deploy
# keys, are carried over from an existing "main" ruleset.
existing=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id')
keep_rules=""
keep_bypass=""
if [ -n "$existing" ]; then
  # shellcheck disable=SC2016
  keep_rules=$(gh api "repos/$repo/rulesets/$existing" --jq '[.rules[] | select(.type | IN("deletion","non_fast_forward","required_linear_history","required_signatures","pull_request","required_status_checks") | not) | {type} + (if .parameters then {parameters} else {} end) | tojson] | join(",")')
  keep_bypass=$(gh api "repos/$repo/rulesets/$existing" --jq '[.bypass_actors[] | select(.actor_type != "DeployKey") | {actor_id, actor_type, bypass_mode} | tojson] | join(",")')
fi
bypass="$keep_bypass"
if [ "$bypass_deploy_keys" = "true" ]; then
  bypass="$bypass${bypass:+,}{\"actor_id\":null,\"actor_type\":\"DeployKey\",\"bypass_mode\":\"always\"}"
fi
checks_rule=""
if [ -n "$required_checks" ]; then
  contexts=""
  old_ifs=$IFS
  IFS='
'
  for c in $required_checks; do
    contexts="$contexts${contexts:+,}{\"context\":\"$c\"}"
  done
  IFS=$old_ifs
  checks_rule=",{\"type\":\"required_status_checks\",\"parameters\":{\"strict_required_status_checks_policy\":false,\"do_not_enforce_on_create\":false,\"required_status_checks\":[$contexts]}}"
fi
extra_rules=""
if [ -n "$keep_rules" ]; then
  extra_rules=",$keep_rules"
fi
ruleset=$(cat <<JSON
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [$bypass],
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
    }}$checks_rule$extra_rules
  ]
}
JSON
)
if [ -n "$existing" ]; then
  printf '%s' "$ruleset" | gh api -X PUT "repos/$repo/rulesets/$existing" --input - >/dev/null
  echo "ruleset main: updated (id $existing)"
else
  printf '%s' "$ruleset" | gh api -X POST "repos/$repo/rulesets" --input - >/dev/null
  echo "ruleset main: created"
fi

echo
show
