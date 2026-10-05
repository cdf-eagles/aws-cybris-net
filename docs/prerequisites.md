# Prerequisites

The tools a workstation needs to plan and apply this repository, and how to
install them on macOS, Fedora, Red Hat Enterprise Linux (RHEL), Ubuntu, and
Debian. `.tool-versions` at the repository root names the exact OpenTofu and
tflint versions; the other tools float with the package manager.

| Tool | Used for | Pinned |
|---|---|---|
| [OpenTofu](https://opentofu.org/) | plan and apply | yes, `.tool-versions` |
| [tflint](https://github.com/terraform-linters/tflint) | lint, with the Amazon Web Services (AWS) ruleset fetched by `tflint --init` | yes, `.tool-versions` |
| [AWS Command Line Interface (CLI) v2](https://aws.amazon.com/cli/) | Identity Center sign-in, proofs | no |
| [pre-commit](https://pre-commit.com/) | runs every check before a commit | no |
| [Checkov](https://www.checkov.io/) | static security checks, `.checkov.yml` | no |
| [terraform-docs](https://terraform-docs.io/) | the tables in each stack `README.md` | no |
| [actionlint](https://github.com/rhysd/actionlint) | lints the workflows | no |
| [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) | the `tofu` wrapper, see the README | no |
| Python 3 with `pipx` | installs pre-commit and Checkov in isolation | no |

A version manager that reads `.tool-versions`, such as
[mise](https://mise.jdx.dev/) or asdf, installs the pinned OpenTofu and tflint
on any of these systems: `mise install` in the repository root. The
per-system steps below install from the package manager instead and may give
a newer version than the pin; `tofu version` and `tflint --version` show what
was installed.

## macOS (Homebrew)

```sh
brew install opentofu awscli pre-commit checkov terraform-docs actionlint pipx
brew install terraform-linters/tap/tflint
brew install --cask 1password-cli
```

tflint left the main Homebrew repository and lives in its own tap, hence the
second line. Homebrew installs the current OpenTofu release, which may be
newer than `.tool-versions`; `tofu version` shows what was installed.

Then, once per clone, from the repository root (the `--config` path must be
the root's `.tflint.hcl`, so it is written out rather than taken from the
current directory):

```sh
cd /path/to/aws-cybris-net
pre-commit install
tflint --init --config /path/to/aws-cybris-net/.tflint.hcl
```

## Fedora and RHEL

OpenTofu ships its own repository through the installer script; AWS CLI v2
is in Fedora's repositories as `awscli2` and installed from the official
archive on RHEL; tflint, terraform-docs, and actionlint are single binaries
from their GitHub releases; the 1Password CLI has its own repository.

```sh
# OpenTofu (adds the packages.opentofu.org repository)
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method rpm
rm install-opentofu.sh

# AWS CLI v2: Fedora
sudo dnf install -y awscli2 pipx unzip
# AWS CLI v2: RHEL (no package; official archive)
sudo dnf install -y pipx unzip
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# pre-commit and Checkov, isolated from the system Python
pipx install pre-commit
pipx install checkov

# tflint (the version in .tool-versions), terraform-docs, actionlint: release binaries into /usr/local/bin
curl -fsSLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/tflint_linux_amd64.zip
curl -fsSLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/checksums.txt
sha256sum --ignore-missing -c checksums.txt
unzip -q tflint_linux_amd64.zip && sudo install -m 0755 tflint /usr/local/bin/tflint && rm tflint tflint_linux_amd64.zip checksums.txt
curl -fsSL https://github.com/terraform-docs/terraform-docs/releases/download/v0.24.0/terraform-docs-v0.24.0-linux-amd64.tar.gz | tar -xz terraform-docs
sudo install -m 0755 terraform-docs /usr/local/bin/terraform-docs && rm terraform-docs
curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
sudo install -m 0755 actionlint /usr/local/bin/actionlint && rm actionlint
```

1Password CLI: follow the Red Hat Package Manager (RPM) steps at
<https://developer.1password.com/docs/cli/get-started/>; they add the
1Password repository and its signing key, then `sudo dnf install 1password-cli`.

## Ubuntu and Debian

```sh
# OpenTofu (adds the packages.opentofu.org repository)
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method deb
rm install-opentofu.sh

# AWS CLI v2 from the official archive (the apt package lags)
sudo apt-get update && sudo apt-get install -y pipx unzip curl
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# pre-commit and Checkov, isolated from the system Python
pipx install pre-commit
pipx install checkov

# tflint (the version in .tool-versions), terraform-docs, actionlint: release binaries into /usr/local/bin
curl -fsSLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/tflint_linux_amd64.zip
curl -fsSLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/checksums.txt
sha256sum --ignore-missing -c checksums.txt
unzip -q tflint_linux_amd64.zip && sudo install -m 0755 tflint /usr/local/bin/tflint && rm tflint tflint_linux_amd64.zip checksums.txt
curl -fsSL https://github.com/terraform-docs/terraform-docs/releases/download/v0.24.0/terraform-docs-v0.24.0-linux-amd64.tar.gz | tar -xz terraform-docs
sudo install -m 0755 terraform-docs /usr/local/bin/terraform-docs && rm terraform-docs
curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
sudo install -m 0755 actionlint /usr/local/bin/actionlint && rm actionlint
```

1Password CLI: follow the Debian and Ubuntu steps at
<https://developer.1password.com/docs/cli/get-started/>; they add the
1Password repository and its signing key, then `sudo apt-get install 1password-cli`.

On an arm64 machine replace `linux-amd64` and `linux-x86_64` in the
archive names with `linux-arm64` and `linux-aarch64`.

## After installing, on every system

```sh
cd /path/to/aws-cybris-net
pre-commit install
tflint --init --config /path/to/aws-cybris-net/.tflint.hcl
pre-commit run --all-files
```

`tflint --init` downloads the AWS ruleset named in `.tflint.hcl` into
`~/.tflint.d/plugins`; it is not tied to the stack directory, so it runs once
per workstation, not per stack. The `tofu_tflint` pre-commit hook passes the
same `--config`, so a plugin that is missing shows up as that hook failing.

`pre-commit run --all-files` must pass before the first commit; it is the
same set of checks the Validate workflow runs. Then configure the AWS CLI as
the README's "First-time AWS CLI setup" describes.
