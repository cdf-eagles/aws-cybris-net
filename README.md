# aws-cybris-net

Infrastructure as code for the `cybris.net` Amazon Web Services (AWS) account:
the account baseline, the network, and the hosts that serve public Domain Name
System (DNS), Network Time Protocol (NTP), and web services. Everything is
OpenTofu. During the adoption of the existing environment, plans and applies
run from a workstation; once every stack is adopted, continuous integration
(CI) plans every pull request and applies `main` through roles that GitHub
Actions assumes with OpenID Connect (OIDC), see "Continuous integration".

[![Validate](https://github.com/cdf-eagles/aws-cybris-net/actions/workflows/validate.yml/badge.svg)](https://github.com/cdf-eagles/aws-cybris-net/actions/workflows/validate.yml)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit)](https://github.com/pre-commit/pre-commit)

## Layout

Stacks are ordered by lifecycle, not by resource type: the lower the number,
the less often it changes and the more it protects.

| Stack | Holds | State | Applied with |
|---|---|---|---|
| `stacks/00-bootstrap` | the Simple Storage Service (S3) bucket that stores every stack's state, its own included | `aws-cybris-net/00-bootstrap.tfstate` | administrator |
| `stacks/10-account` | identity (Identity and Access Management (IAM) Identity Center permission sets, OpenID Connect roles for GitHub Actions), CloudTrail, GuardDuty, Config, budgets, cost anomaly alerts, contacts | `aws-cybris-net/10-account.tfstate` | administrator |
| `stacks/20-platform` | Virtual Private Cloud (VPC), subnets, security groups, Key Management Service (KMS) key, Elastic Internet Protocol (IP) address (EIP), data volumes, snapshot policy | `aws-cybris-net/20-platform.tfstate` | engineer |
| `stacks/30-hosts/<name>` | one instance per directory, its volume attachments, EIP association, and status-check alarm; the only stacks that are ever destroyed | `aws-cybris-net/30-hosts-<name>.tfstate` | engineer |
| `modules/` | code shared by the stacks | -- | -- |

Stacks read each other's **identifiers only** through `terraform_remote_state`
outputs. No stack exports whole objects.

## Rules

- **Nothing in the running environment is stopped, replaced, or deleted by an
  apply.** Existing resources are adopted with `import` blocks. A plan that
  shows `destroy` or `replace` is a failed change, not a judgment call. The
  EIP, the data volumes, the KMS key, the VPC, and the state bucket carry
  `prevent_destroy`.
- Every stack pins `required_version` and the AWS provider, and commits its
  `.terraform.lock.hcl`.
- Credentials come from IAM Identity Center (`aws sso login`) for people and
  from OIDC-assumed roles for CI; no access keys are stored anywhere. The
  administrator profile is `cybris`; further permission sets get
  `cybris-<permission set>`.
- Tags: the provider's `default_tags` set `Project`, `Environment`, `Owner`,
  `ManagedBy`, `Repository`, and `Stack` on every resource; a resource adds only
  `Name` and purpose tags such as `Backup` or `Protected`.
- Comments explain an action that is not obvious. Reasoning goes in
  `CHANGELOG.md` and the commit message.

## Prerequisites

- [OpenTofu](https://opentofu.org/) and [tflint](https://github.com/terraform-linters/tflint)
  at the versions in `.tool-versions`.
- [AWS Command Line Interface (CLI)](https://aws.amazon.com/cli/) v2 with an
  Identity Center session configured (`aws configure sso`).
- [pre-commit](https://pre-commit.com/): `pre-commit install` once per clone.
  The hooks run `tofu fmt`, `tofu validate`, tflint, Checkov, terraform-docs,
  secret scanning, and actionlint.

Installation on macOS (Homebrew), Fedora, Red Hat Enterprise Linux, Ubuntu,
and Debian is in [docs/prerequisites.md](docs/prerequisites.md).

## First-time AWS CLI setup

Access is through IAM Identity Center, which the AWS CLI still calls single
sign-on (SSO); nothing is applied with an access key. Once per workstation,
create a session and a profile:

```sh
aws configure sso
```

Answer the prompts as follows; everything else keeps its default:

| Prompt | Value |
|---|---|
| SSO session name | `cybris` |
| SSO start uniform resource locator (URL) | the Identity Center start URL of the account (`https://<alias>.awsapps.com/start`) |
| SSO region | `us-east-1` |
| SSO registration scopes | `sso:account:access` |
| account | the account ID shown on the Identity Center start page |
| role (permission set) | `AdministratorAccess` for `00-bootstrap` and `10-account`; `EngineerLead` for the other stacks |
| default client region | `us-east-1` |
| profile name | `cybris` for the administrator set, `cybris-<permission set>` for the others |

The result in `~/.aws/config` looks like this; it can also be written by hand:

```ini
[profile cybris]
region = us-east-1
sso_session = cybris
sso_account_id = <account id>
sso_role_name = AdministratorAccess

[sso-session cybris]
sso_start_url = https://<alias>.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

One `sso-session` block serves every profile; add a `[profile cybris-<set>]`
block per permission set, differing only in `sso_role_name`. Sign in with
`aws sso login --profile cybris` (the browser opens once; the session lasts as
long as the permission set allows) and check with
`aws sts get-caller-identity --profile cybris`.

## Working a stack

```sh
aws sso login --profile cybris
export AWS_PROFILE=cybris
cd stacks/00-bootstrap
tofu init
tofu plan -out tf.plan
tofu show tf.plan        # read it: 0 to destroy, 0 to replace
tofu apply tf.plan
```

## 1Password integration

The workstation shell wraps `tofu` in [1Password CLI](https://developer.1password.com/docs/cli/)'s
`op run`, so any `op://` reference in the environment is resolved at run
time and secrets never sit in a file:

```sh
run_tofu () {
  if [ -e "op.env" ]; then
    op run --env-file=op.env -- tofu "$@"
  else
    op run -- tofu "$@"
  fi
}
alias tofu=run_tofu
```

This repository has no `op.env`: credentials are Identity Center sessions,
so `op run` passes the environment through unchanged and only `AWS_PROFILE`
matters. Export it once per shell rather than prefixing each command, because
a `VAR=value tofu ...` prefix is not reliably alias-expanded.

A stack that ever needs a secret (an application programming interface (API)
token for a provider, say) gets an `op.env` next to its code, one variable per
line, each value an `op://<vault>/<item>/<field>` reference (or
`op://<vault>/<item>/<section>/<field>` when the item has sections):

```sh
TF_VAR_provider_token = "op://<Vault Name>/<item>/credential"
```

`op.env` is ignored by git because a reference names the vault and the item;
commit an `op.env.example` with the same variables and placeholder item names
instead. `op run` resolves the references at run time and masks the values in
output, so a plan that prints one shows it redacted. The previous
repositories' `op.env` files held a static access-key pair; that pair is
retired with them and nothing here recreates it.

Every stack, `00-bootstrap` included, keeps its state in the bucket with the
native S3 lock file; no DynamoDB table is involved.

## Creating the state bucket from nothing

`00-bootstrap` stores its state in the bucket it manages, so on an account
where the bucket does not exist yet the first apply runs with a local backend
and the state is moved into the bucket afterwards. Bucket names are global:
set the name in both `variables.tf` (`state_bucket_name`) and the `backend`
block of `versions.tf` before starting.

```sh
aws sso login --profile cybris
cd stacks/00-bootstrap
mv imports.tf imports.tf.off       # nothing exists to import yet
printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
AWS_PROFILE=cybris tofu init
AWS_PROFILE=cybris tofu plan -out tf.plan
AWS_PROFILE=cybris tofu apply tf.plan
rm backend_override.tf
AWS_PROFILE=cybris tofu init -migrate-state
rm terraform.tfstate terraform.tfstate.backup imports.tf.off
```

`backend_override.tf` is ignored by git (`*_override.tf`) and must not be
committed. `-migrate-state` copies the local state into the bucket under the
key in `versions.tf`; the local files are then surplus.

## Adopting an existing state bucket

When the bucket already exists (this account's case: it was created by an
earlier repository), nothing is created. The stack adopts the bucket and its
settings with `import` blocks, which OpenTofu evaluates during `plan` and
`apply` and which become inert once the state holds the resources. The blocks
used on 2026-10-04 were in `stacks/00-bootstrap/imports.tf`, removed after
the apply:

```hcl
import {
  to = aws_s3_bucket.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_versioning.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_public_access_block.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_ownership_controls.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.state
  id = var.state_bucket_name
}
```

Only settings the bucket already has are imported; the lifecycle rule and
the bucket policy are created because the bucket had none. A setting that
exists but is not imported would be created again and fail, and a setting
that is imported but does not exist fails the plan with "resource not found",
so read `aws s3api get-bucket-*` first and import exactly what is there.
The backend in `versions.tf` is already S3, so the first `tofu init` writes
only the new state key; the plan must then show `N to import, ... 0 to
destroy` with every change an addition or an in-place update. Any
`replace` means a declared attribute disagrees with the bucket: fix the code
to match, never the bucket to match the code.

The same pattern adopts every other existing resource in later stacks: one
`import` block per resource, a plan with no destroy and no replace, and the
blocks deleted in the commit that records the apply.

## Checks

`pre-commit run --all-files` runs everything the Validate workflow runs. The
workflow runs only on pull requests that change OpenTofu code or the check
configuration, and needs no AWS credentials.

## Repository settings

`scripts/configure-github.sh` applies the GitHub settings with the GitHub
CLI, signed in as an owner, and is safe to run again; `--show` prints the
current state without changing it. It sets: squash as the only merge method
with the branch deleted on merge; secret scanning with push protection;
Dependabot alerts, security updates, and private vulnerability reporting;
Actions limited to GitHub's own actions plus the two pinned third-party ones,
with a read-only default token; and a ruleset on `main` that requires a pull
request, the `validate` check, signed commits, and linear history, and
forbids force-pushes and deletion. `.github/dependabot.yml` keeps the pinned
actions and the provider constraints current with one grouped pull request a
week, after a seven-day cooldown on new releases.

```sh
sh scripts/configure-github.sh --show
sh scripts/configure-github.sh
```

## Continuous integration

Reached stack by stack: a stack joins CI once it is adopted and its plan is
clean from a workstation.

| Workflow | Trigger | Role | Does |
|---|---|---|---|
| Validate | every pull request | none | format, validate, tflint, Checkov |
| Plan | every pull request | `gha-aws-cybris-net-plan` (ReadOnlyAccess plus state read) | `tofu plan` of `20-platform` and `30-hosts/persephone`, summary line in the job summary; **fails if the plan would destroy or replace anything** |
| Apply | not yet | `gha-aws-cybris-net-apply` (the EngineerLead policy) | decided 2026-10-05: applies stay on a workstation until the rebuild of the host is done; the workflow and its role follow afterwards |

The trust policies of the OIDC roles name each repository by both subject
shapes GitHub issues, the original and the immutable one with owner and
repository IDs (`10-account`, `github_repository_ids`); a new repository
needs its ID added there before its first run.

The Plan workflow needs four repository secrets, set once by hand:
`AWS_PLAN_ROLE_ARN` (the `gha_aws_cybris_net_plan_role_arn` output of
`10-account`; it carries the account ID, which is why it is a secret), and
`TF_VAR_KEY_PAIR_NAME`, `TF_VAR_LOGIN_ACCOUNT_NAME`, and
`TF_VAR_LOGIN_ACCOUNT_UID` (the values the host stack's `op.env` supplies). The
job exchanges its OpenID Connect token for a session with the runner's own
AWS command line interface (CLI), so no third-party action handles
credentials. Plans take no state lock; nothing in CI writes to the bucket.

`00-bootstrap` and `10-account` are applied from a workstation, not CI:
the first owns the bucket the CI roles read state from, the second creates
those roles and holds the account's identity configuration. Their state is
in the bucket like every other stack's.
