#!/bin/sh
# Applies the standard GitHub settings to one public repository with the
# GitHub CLI (gh), signed in as an owner. Safe to run again: every call sets
# state rather than adding it. Per-repository values (allowed third-party
# actions, required checks, deploy-key bypass, release flow) are read from
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
  for f in "$here"/github-settings/*.conf "$here"/github-settings/.*.conf; do
    if [ -f "$f" ]; then printf ' %s' "$(basename "$f" .conf)" >&2; fi
  done
  echo >&2
  exit 2
fi
case "$mode" in apply|--show) ;; *) echo "unknown option: $mode" >&2; exit 2 ;; esac

allowed_actions=""
required_checks=""
bypass_deploy_keys="false"
release_flow="false"
develop_required_checks=""
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

# Prints a required_status_checks rule (with a leading comma) for the
# newline-separated check names given, or nothing when there are none.
checks_json() {
  [ -n "$1" ] || return 0
  contexts=""
  old_ifs=$IFS
  IFS='
'
  for c in $1; do
    contexts="$contexts${contexts:+,}{\"context\":\"$c\"}"
  done
  IFS=$old_ifs
  printf ',{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"do_not_enforce_on_create":false,"required_status_checks":[%s]}}' "$contexts"
}

# Creates the named ruleset, or replaces it in place when it exists.
put_ruleset() {
  rs_name="$1"; rs_id="$2"; rs_json="$3"
  if [ -n "$rs_id" ]; then
    printf '%s' "$rs_json" | gh api -X PUT "repos/$repo/rulesets/$rs_id" --input - >/dev/null
    echo "ruleset $rs_name: updated (id $rs_id)"
  else
    printf '%s' "$rs_json" | gh api -X POST "repos/$repo/rulesets" --input - >/dev/null
    echo "ruleset $rs_name: created"
  fi
}

# The repository administrator role (id 5), allowed to bypass a ruleset.
admin_bypass='{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}'

# Ruleset on the default branch: signed commits, linear history, no
# force-push, no deletion, and either a pull request (squash) with the listed
# checks, or, for a release-flow repository, updates restricted to
# administrators, who fast-forward main to a proven release candidate.
# Rule types this script does not manage, and bypass actors other than deploy
# keys (and, in a release flow, the administrator role it adds), are carried
# over from an existing "main" ruleset.
existing=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id')
keep_rules=""
keep_bypass=""
if [ -n "$existing" ]; then
  # shellcheck disable=SC2016
  keep_rules=$(gh api "repos/$repo/rulesets/$existing" --jq '[.rules[] | select(.type | IN("deletion","non_fast_forward","required_linear_history","required_signatures","pull_request","required_status_checks","update") | not) | {type} + (if .parameters then {parameters} else {} end) | tojson] | join(",")')
  keep_bypass=$(gh api "repos/$repo/rulesets/$existing" --jq '[.bypass_actors[] | select(.actor_type != "DeployKey") | select((.actor_type == "RepositoryRole" and .actor_id == 5) | not) | {actor_id, actor_type, bypass_mode} | tojson] | join(",")')
fi
bypass="$keep_bypass"
if [ "$bypass_deploy_keys" = "true" ]; then
  bypass="$bypass${bypass:+,}{\"actor_id\":null,\"actor_type\":\"DeployKey\",\"bypass_mode\":\"always\"}"
fi
checks_rule=$(checks_json "$required_checks")
if [ "$release_flow" = "true" ]; then
  bypass="$bypass${bypass:+,}$admin_bypass"
  entry_rule='{"type": "update", "parameters": {"update_allows_fetch_and_merge": false}}'
else
  entry_rule='{"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true,
      "allowed_merge_methods": ["squash"]
    }}'
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
    $entry_rule$checks_rule$extra_rules
  ]
}
JSON
)
put_ruleset main "$existing" "$ruleset"

if [ "$release_flow" = "true" ]; then
  # Release flow: develop takes squash-merged pull requests with the listed
  # checks; release tags v* are created by administrators only and can never
  # be moved or deleted. Rule types and bypass actors this script does not
  # manage are carried over from an existing "develop" ruleset.
  dev_id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "develop") | .id')
  dev_keep=""
  dev_bypass=""
  if [ -n "$dev_id" ]; then
    # shellcheck disable=SC2016
    dev_keep=$(gh api "repos/$repo/rulesets/$dev_id" --jq '[.rules[] | select(.type | IN("deletion","non_fast_forward","required_linear_history","required_signatures","pull_request","required_status_checks") | not) | {type} + (if .parameters then {parameters} else {} end) | tojson] | join(",")')
    dev_bypass=$(gh api "repos/$repo/rulesets/$dev_id" --jq '[.bypass_actors[] | {actor_id, actor_type, bypass_mode} | tojson] | join(",")')
  fi
  dev_checks=$(checks_json "$develop_required_checks")
  dev_extra=""
  if [ -n "$dev_keep" ]; then
    dev_extra=",$dev_keep"
  fi
  develop_rs=$(cat <<JSON
{
  "name": "develop",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [$dev_bypass],
  "conditions": {"ref_name": {"include": ["refs/heads/develop"], "exclude": []}},
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
    }}$dev_checks$dev_extra
  ]
}
JSON
)
  put_ruleset develop "$dev_id" "$develop_rs"

  create_id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "release-tags-create") | .id')
  create_rs=$(cat <<JSON
{
  "name": "release-tags-create",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [$admin_bypass],
  "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
  "rules": [{"type": "creation"}]
}
JSON
)
  put_ruleset release-tags-create "$create_id" "$create_rs"

  fixed_id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "release-tags-immutable") | .id')
  fixed_rs=$(cat <<JSON
{
  "name": "release-tags-immutable",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
  "rules": [{"type": "update"}, {"type": "deletion"}]
}
JSON
)
  put_ruleset release-tags-immutable "$fixed_id" "$fixed_rs"
fi

echo
show
