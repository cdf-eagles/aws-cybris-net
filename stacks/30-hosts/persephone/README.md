# 30-hosts/persephone

The host that serves public Domain Name System (DNS), Network Time Protocol
(NTP), and web services: the instance and its root volume, the primary
network interface, the two data-volume attachments, and the Elastic Internet
Protocol (IP) address (EIP) association. Everything that existed was adopted
with `import` blocks. The image and the user data serve the first boot of an
instance only and every plan ignores them, so the instance is replaced only
by an explicit `tofu apply -replace=aws_instance.this` in a rebuild window.

Applied from a workstation with the engineer profile. State:
`aws-cybris-net/30-hosts-persephone.tfstate`. The network, security group,
key, address, and volumes come from `20-platform`, read through that stack's
outputs. First applied 2026-10-05 (5 imported, 0 added, 2 changed, 0
destroyed; the host's uptime was unchanged); the `import` blocks were
removed once the state held the adopted resources.

## Alarm

`aws_cloudwatch_metric_alarm.status_check_failed` watches the
`StatusCheckFailed` metric of the instance, which covers both the system and
the instance status check. It takes the maximum over 300 seconds and enters
`ALARM` when one of the last two periods is at or above 1. The alarm and the
recovery both go to the `account-alerts` Simple Notification Service (SNS)
topic of `10-account`, whose Amazon Resource Name (ARN) this stack reads from
that stack's state, so `10-account` must be applied before this stack on an
account that has neither.

## What changes on adoption

- The primary interface takes one Internet Protocol version 6 (IPv6) address
  from its subnet's /64, in place. The interface is adopted as its own
  resource because the address count on the instance resource would replace
  the instance. The host still needs its own configuration to use the
  address; that is the `persephone.cybris.net` Ansible's job.
- Termination protection is switched on. The guard rails already deny
  terminating anything tagged `Protected = true`, but that denial binds the
  Identity Center sessions only; the instance flag binds everything.
- The root volume gains `Backup = daily`, which puts it on the daily
  snapshot schedule beside the data volumes, and `Protected = true`.
- Tags: `Owner` becomes `infrastructure` and `CostCenter` goes, matching the
  provider's `default_tags`.
- The central processing unit (CPU) credit mode stays `unlimited` as found; at the host's load it never
  bursts past its baseline, so it never bills.

## Secrets and personal data

`op.env` (ignored by git; copy `op.env.example`) supplies three values
through 1Password references: the key pair name, because it carries an
account name, and the name and user ID (UID) of the personal login account
that the first boot creates. The three variables are sensitive and have no
default; the Plan workflow reads the same values from repository secrets.

## User data

`user_data.sh` runs once, as root, at the first boot of a new instance; the
image's `ec2_configinit` runs it before `ec2_fetchkey` creates `ec2-user`.
`templatefile()` fills in the login account's name, user ID (UID), and group ID (GID). In order, it:

1. installs `python3` and `sudo` and gives `ec2-user` a sudo rule without a
   password, so Ansible can connect and become root;
2. sets `canmount=off` on the image's empty `zroot/home` and unmounts it, so
   it cannot hide the home volume;
3. adds `/dev/gpt/homedirs` on `/home` and `/dev/gpt/apachedirs` on
   `/usr/local/www/apache24` to `/etc/fstab`, checks each file system, and
   mounts it; a missing label is logged, and no volume is ever formatted;
4. creates the login account with its UID and a primary group with its GID, the
   home `/home/<name>`, the shell `/bin/sh`, no password, and no other
   group, unless the name or the number is taken; it creates the home
   directory only when the volume has none and changes no existing file;
5. creates `ec2-user` with the fixed IDs 1000:1000, in `wheel`, and hands
   `/home/ec2-user` on the home volume to it when another ID owns it, so
   `sshd` accepts the home; an existing `ec2-user` with other IDs is logged
   as a failure.

The login account's IDs must be from 500 to 999 and `ec2-user`'s are 1000:
both stay below the 1001 upward that the image's own accounts take (its
`ssm-user` is 1001), so no first boot finds them taken.

Each step checks before it acts, so a second run changes nothing. The script
logs to `/var/log/user_data.log`, ending with `user_data end <time>, <n>
failure(s)`. Everything after the first boot is the `persephone.cybris.net`
Ansible's job, the login account's password (`--tags user-config`), shell,
and groups included. Because the image and the user data are in
`ignore_changes`, editing either changes nothing until the next explicit
replacement.

## First apply (done 2026-10-05; kept for a new account)

Every command runs from this directory with `op.env` in place; `tofu` is the
1Password wrapper from the repository README.

1. **Plan and read it.** Expected, on this account's first apply: 5 to
   import; 0 to add; 2 to change (the instance for termination protection
   and tags, the interface for the IPv6 address and tags); **0 to destroy,
   0 to replace**. A plan that offers to replace the instance means an
   argument disagrees with what the account holds; fix the argument.

   ```sh
   export AWS_PROFILE=cybris-engineer
   tofu init
   tofu plan -out tf.plan
   tofu show tf.plan | grep -E "^Plan:|must be replaced|will be destroyed|Error"
   ```

2. **Apply, then prove the host never noticed:**

   ```sh
   tofu apply tf.plan
   tofu plan -detailed-exitcode; echo "plan exit: $?"
   tofu output ipv6_addresses
   aws ec2 describe-instances --instance-ids "$(tofu output -raw instance_id)" --query 'Reservations[0].Instances[0].[State.Name,LaunchTime]'
   aws ec2 describe-instance-attribute --instance-id "$(tofu output -raw instance_id)" --attribute disableApiTermination --query DisableApiTermination.Value
   ```

   The state is `running` with the original launch time, and the uptime on
   the host itself is unchanged. The termination-protection read can trail
   the apply by a few seconds; a plan run at once may still offer the
   change, and the next one is clean.

3. **Afterwards:** delete `imports.tf` and commit; the list below keeps the
   identifiers.

## What was imported

| Resource | Identifier |
|---|---|
| `aws_instance.this` | `i-046f0e6673e45e6e5` |
| `aws_network_interface.primary` | `eni-01cc33cc68b16c4cc` |
| `aws_volume_attachment.data["home"]`, `["web"]` | `/dev/xvdbb:vol-00120fb20ff72e79c:i-046f0e6673e45e6e5`, `/dev/xvdbc:vol-0bf39b92006003b08:i-046f0e6673e45e6e5` |
| `aws_eip_association.this` | `eipassoc-0059822721a6b7c84` |

## The rebuild window

A rebuild replaces the instance and its root volume and keeps everything
else: the data volumes, the primary interface with its private and IPv6
addresses, and the EIP association. It is applied from a workstation on the
feature branch, because the Plan check refuses any replacement. The full
procedure, with its captures and rollback, is kept in the internal runbook;
in short:

1. **Lift protection** (`disable_api_termination = false`, `Protected` off
   the instance's own tags only), plan, and apply: 0 to add, 1 to change, 0
   to destroy.
2. **First rebuild only:** switch the primary interface's attachment to
   delete-on-termination off, so terminating the old instance keeps the
   interface; later instances are launched on it with the flag already off.

   ```sh
   aws ec2 modify-network-interface-attribute --network-interface-id <interface id> --attachment AttachmentId=<attachment id>,DeleteOnTermination=false
   ```

3. **Keep the state that lives only on the root volume** by copying it to
   the home volume, then stop the services and the instance, so the data
   volumes are detached from a stopped host.
4. **Replace**, always with `-replace`: a plan without it never rebuilds,
   and a changed `instance_type` alone would stop and resize the old
   instance in place.

   ```sh
   tofu plan -replace=aws_instance.this -out tf.plan
   tofu show tf.plan | grep -E "^Plan:|must be replaced|will be destroyed|will be updated|Error"
   tofu apply tf.plan
   ```

   Expected: 3 to add, 1 to change, 3 to destroy. The instance and the two
   volume attachments are replaced and the alarm's instance dimension is
   updated; a plan that touches the interface, the EIP association, the
   volumes, or the address is wrong.
5. **Prove the host and run the Ansible**, then restore protection, plan,
   and apply (0 to add, 1 to change, 0 to destroy). The next plan shows no
   changes, and the pull request's Plan check passes because nothing is
   replaced against state.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.67.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_metric_alarm.status_check_failed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_eip_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_association) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_network_interface.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_volume_attachment.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment) | resource |
| [terraform_remote_state.account](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.platform](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_key_pair_name"></a> [key\_pair\_name](#input\_key\_pair\_name) | Name of the EC2 key pair the instance was launched with; supplied by op.env, never committed, because the name carries an account name. | `string` | n/a | yes |
| <a name="input_login_account_gid"></a> [login\_account\_gid](#input\_login\_account\_gid) | Group ID (GID) of the login account's primary group, which already owns its home directory on the home volume; supplied by op.env, never committed. | `number` | n/a | yes |
| <a name="input_login_account_name"></a> [login\_account\_name](#input\_login\_account\_name) | Name of the personal login account the first boot creates; supplied by op.env, never committed. | `string` | n/a | yes |
| <a name="input_login_account_uid"></a> [login\_account\_uid](#input\_login\_account\_uid) | User ID (UID) of the login account, which already owns its home directory on the home volume; supplied by op.env, never committed. | `number` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region the host lives in; must match 20-platform. | `string` | `"us-east-1"` | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | Bucket that stores OpenTofu state, from 00-bootstrap; this stack reads 20-platform's outputs from it. | `string` | `"cybris-net-tf-bucket"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | The instance. |
| <a name="output_ipv6_addresses"></a> [ipv6\_addresses](#output\_ipv6\_addresses) | The IPv6 addresses on the primary interface, for the AAAA records. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | The instance's private IPv4 address. |
<!-- END_TF_DOCS -->
