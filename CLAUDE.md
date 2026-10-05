# Conventions for this repository

This file carries only what is specific to `aws-cybris-net`. Writing,
commit-message, and backlog rules live in the account's own notes and are not
repeated here.

## What the code must never do

- Plan a `destroy` or a `replace` of anything that exists in the account.
  Existing resources are adopted with `import` blocks, and a plan is proven
  clean (`0 to destroy, 0 to replace`) before it is applied.
- Store or reference an access key. Credentials are Identity Center sessions
  for people and OIDC-assumed roles for GitHub Actions.
- Name a person in code, comments, documentation, changelog entries, or commit
  messages. Decisions are attributed by date or role.
- Hard-code the account ID or any other account identifier. Code reads it
  from `aws_caller_identity`; documentation shows `<account id>` and says
  where the reader finds the real value.

## Shape

- One stack per lifecycle (`00-bootstrap`, `10-account`, `20-platform`,
  `30-hosts/<name>`); one state key per stack; cross-stack references carry
  identifiers only.
- Every stack has `versions.tf` (pinned `required_version` and provider),
  `providers.tf` with `default_tags`, `variables.tf`, `locals.tf`, `main.tf`,
  `outputs.tf`, and `imports.tf` while adoption is in progress. Each stack
  directory has a `README.md` with a terraform-docs block.
- Security-group rules use `aws_vpc_security_group_ingress_rule` and
  `aws_vpc_security_group_egress_rule`, one resource per rule, never the
  legacy `aws_security_group_rule` or inline rule blocks.
- Comments explain an action that is not obvious; reasoning goes in
  `CHANGELOG.md` and the commit message. `CHANGELOG.md` is one bullet per day,
  dated, with that day's items nested under it, one to two sentences each.

## Before a commit is staged

`pre-commit run --all-files` must pass. It runs `tofu fmt`, `tofu validate`
(with `-backend=false`), tflint with the Amazon Web Services (AWS) ruleset, Checkov with
`.checkov.yml`, terraform-docs on every stack `README.md`, secret scanning, and
actionlint. GitHub Actions minutes are limited, so the pull-request workflow
is not the place to find a formatting error.

## Writing rule: expand an acronym at first use

The first use of an acronym in any document, including a commit message,
spells out what it stands for: the full term, then the acronym in parentheses.
After that the acronym stands alone. Every document stands alone and expands
at its own first use; headings and table cells count; well-known acronyms are
not exempt. Literal text (file names, flags, hostnames, and command output) stays
literal, and the first prose mention of such a literal expands it once. Units
of measure, proper product names (FreeBSD and OpenTofu), and command names that
are not initialisms are not acronyms.

## Writing rule: the Oxford comma

A list of three or more items carries a comma before the final "and" or
"or": "format, validate, and lint". This holds in every document, comment,
and commit message.
