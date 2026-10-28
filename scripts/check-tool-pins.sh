#!/bin/sh
# Fails when a tool version written down for workstations (.tool-versions and
# the download lines of docs/prerequisites.md) differs from the workflow env:
# pin that CI installs. The weekly Tool drift job reads only the workflow pins,
# so this check is what keeps the other copies in step.
#
#   sh scripts/check-tool-pins.sh            # the repository holding the script
#   sh scripts/check-tool-pins.sh <root>     # another checkout, for tests
set -eu

root=${1:-$(dirname -- "$0")/..}
tv="$root/.tool-versions"
validate="$root/.github/workflows/validate.yml"
plan="$root/.github/workflows/plan.yml"
docs="$root/docs/prerequisites.md"
bad=0

for f in "$tv" "$validate" "$plan" "$docs"; do
  [ -f "$f" ] || { echo "missing: $f"; exit 1; }
done

# One value or "?": a pin found twice or not at all prints "?", which check
# always fails (bad=1 set here would be lost in the command substitution).
one() {
  [ "$(printf '%s\n' "$2" | grep -c .)" -eq 1 ] && { printf '%s\n' "$2"; return; }
  echo "$1: expected exactly one pin, found: $(printf '%s' "$2" | tr '\n' ' ')" >&2
  echo "?"
}

# .tool-versions line "<tool> <version>"
tool() { one ".tool-versions $1" "$(awk -v t="$1" '$1 == t {print $2}' "$tv")"; }

# workflow top-level env line "  NAME: [v]1.2.3", quotes and leading v dropped
envpin() {
  one "${1##*/} $2" "$(sed -n "s/^  $2: *[\"']\{0,1\}v\{0,1\}\([0-9][^\"' #]*\).*/\1/p" "$1")"
}

# every release-download version for owner/repo in the docs, one per line
docpins() {
  grep -oE "github\.com/$1/releases/download/v[0-9][^/]*/" "$docs" |
    sed 's|.*/download/v||; s|/$||'
}

check() { # tool, expected, label, value
  if [ "$2" = "?" ] || [ "$4" = "?" ] || [ "$4" != "$2" ]; then
    echo "$1: $3 has $4, .tool-versions has $2"
    bad=1
  fi
}

check_docs() { # tool, expected, owner/repo
  pins=$(docpins "$3")
  if [ -z "$pins" ]; then
    echo "$1: docs/prerequisites.md has no $3 download line"
    bad=1
    return
  fi
  for v in $pins; do
    check "$1" "$2" "a docs/prerequisites.md download line" "$v"
  done
}

tofu=$(tool opentofu)
tflint=$(tool tflint)
tfdocs=$(tool terraform-docs)

check opentofu "$tofu" "validate.yml TOFU_VERSION" "$(envpin "$validate" TOFU_VERSION)"
check opentofu "$tofu" "plan.yml TOFU_VERSION" "$(envpin "$plan" TOFU_VERSION)"
check tflint "$tflint" "validate.yml TFLINT_VERSION" "$(envpin "$validate" TFLINT_VERSION)"
check_docs tflint "$tflint" terraform-linters/tflint
check terraform-docs "$tfdocs" "validate.yml TERRAFORM_DOCS_VERSION" "$(envpin "$validate" TERRAFORM_DOCS_VERSION)"
check_docs terraform-docs "$tfdocs" terraform-docs/terraform-docs

if [ "$bad" -ne 0 ]; then
  echo "tool pins disagree; change every copy together"
  exit 1
fi
echo "tool pins agree: opentofu $tofu, tflint $tflint, terraform-docs $tfdocs"
