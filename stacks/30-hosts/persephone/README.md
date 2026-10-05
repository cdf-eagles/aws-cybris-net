# 30-hosts/persephone

The host that serves public Domain Name System (DNS), Network Time Protocol
(NTP), and web services: the instance and its root volume, the primary
network interface, the two data-volume attachments, and the Elastic Internet
Protocol (IP) address (EIP) association. Everything that existed is adopted
with `import` blocks. The image, the user data, and the instance type are
adopted as found and ignored by every plan until the rebuild window, which
is the one change allowed to replace this instance.

Applied from a workstation with the engineer profile. State:
`aws-cybris-net/30-hosts-persephone.tfstate`. The network, security group,
key, address, and volumes come from `20-platform`, read through that stack's
outputs. First applied 2026-10-05 (5 imported, 0 added, 2 changed, 0
destroyed; the host's uptime was unchanged); the `import` blocks were
removed once the state held the adopted resources.

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

`op.env` (ignored by git; copy `op.env.example`) supplies the key pair name
through a 1Password reference, because the name carries an account name.

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

Item 129's runbook, not this README. Only there: a new image, a new instance
type, `user_data` reduced to mounting the volumes and bootstrapping Ansible,
and `ignore_changes` removed. The data volumes and the EIP are reattached to
the new instance, so DNS data and the public address do not change.

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
| [aws_eip_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_association) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_network_interface.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface) | resource |
| [aws_volume_attachment.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment) | resource |
| [terraform_remote_state.platform](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_key_pair_name"></a> [key\_pair\_name](#input\_key\_pair\_name) | Name of the EC2 key pair the instance was launched with; supplied by op.env, never committed, because the name carries an account name. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region the host lives in; must match 20-platform. | `string` | `"us-east-1"` | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | Bucket that stores OpenTofu state, from 00-bootstrap; this stack reads 20-platform's outputs from it. | `string` | `"cybris-net-tf-bucket"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | The instance. |
| <a name="output_ipv6_addresses"></a> [ipv6\_addresses](#output\_ipv6\_addresses) | The IPv6 addresses on the primary interface, for the AAAA records. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | The instance's private IPv4 address. |
<!-- END_TF_DOCS -->
