# 20-platform

The network and the durable data every host depends on: the Virtual Private
Cloud (VPC) with its six subnets, Internet gateway, and route tables, now
dual-stack with an Amazon-provided Internet Protocol version 6 (IPv6) /56; the
security group the hosts attach, one resource per rule, with an IPv6 twin for
every public service; the Key Management Service (KMS) key that encrypts every
volume; the Elastic Internet Protocol (IP) address (EIP) and its reverse
record; the two data volumes; and the Data Lifecycle Manager (DLM) policy that
snapshots them daily. Everything that existed is adopted with `import`
blocks; nothing here is stopped, replaced, or deleted by an apply.

Applied from a workstation with the engineer profile. State:
`aws-cybris-net/20-platform.tfstate`. The role DLM assumes comes from
`10-account`, read through that stack's outputs. First applied 2026-10-05
(36 imported, 12 added, 31 changed, 0 destroyed over two applies, see the
note on the IPv6 egress rule below); the `import` blocks were removed once
the state held the adopted resources.

## What changes on adoption

- The VPC gains an IPv6 /56, each subnet a /64 whose index is the subnet's
  third octet (`10.1.1.0/24` pairs with `…:1::/64`, `10.1.42.0/24` with
  `…:42::/64`), the public subnets assign IPv6 on launch, the public route
  table routes `::/0` to the Internet gateway, and the main route table, which
  the private subnets use, routes `::/0` to a new egress-only gateway. None of
  this touches the running instance; its own IPv6 address is assigned in
  `30-hosts`.
- The security group gains an IPv6 rule for every public service (Domain
  Name System (DNS) over Transmission Control Protocol (TCP) and User
  Datagram Protocol (UDP), Hypertext Transfer Protocol (HTTP), HTTP Secure
  (HTTPS), Network Time Protocol (NTP) over TCP and UDP, DNS over Transport
  Layer Security (TLS)), an Internet Control Message Protocol version 6
  (ICMPv6) echo rule, and an IPv6 egress rule. Secure Shell (SSH) stays
  Internet Protocol version 4 (IPv4)-only from the home
  Internet service provider's ranges until every host is in the tailnet.
  Rule descriptions are rewritten; the rules themselves are unchanged.
- The VPC's own `default` security group, attached to nothing, is adopted
  with no rules, which removes the one egress rule it was created with.
- When the VPC receives its IPv6 block, AWS adds an all-IPv6 egress rule to
  every group that already allows all IPv4 egress. On the hosts' group that
  rule is adopted as the IPv6 egress rule; on the `default` group the next
  plan removes it.
- Tags: `Owner` becomes `infrastructure` and `CostCenter` goes, matching the
  provider's `default_tags`; `Protected = true` lands on the VPC, the EIP,
  the key, and the volumes, which is what the guard rails in `10-account`
  key on; `Backup = daily` lands on the volumes, which is what the DLM policy
  keys on.
- The reverse record of the EIP, set by a `local-exec` provisioner in the
  previous repository, is adopted as `aws_eip_domain_name`.

## First apply (done 2026-10-05; kept for a new account)

Every command runs from this directory; `tofu` is the 1Password wrapper from
the repository README (this stack reads no `op.env`).

1. **Apply `10-account` first, as administrator**, so the DLM role and the
   Identity and Access Management (IAM) `iam:PassRole` grant exist before this stack passes the role. Expected: 1
   role, 1 policy attachment, 1 policy version; 0 to destroy.

   ```sh
   export AWS_PROFILE=cybris
   cd ../10-account
   tofu plan -out tf.plan
   tofu show tf.plan | grep -E "^Plan:|must be replaced|will be destroyed"
   tofu apply tf.plan
   cd ../20-platform
   ```

2. **Switch to the engineer profile** and delete the duplicate security
   group `default-vpc-cybris-net-sg`, which carries the same rules as
   `default-instance-sg` and is attached to nothing. It is deleted by hand
   because this repository never plans a destroy, and it is not adopted
   because adopting it would only be a step toward destroying it.

   ```sh
   export AWS_PROFILE=cybris-engineer
   aws sso login --profile cybris-engineer
   aws ec2 describe-network-interfaces --filters Name=group-id,Values=sg-06060062ed0b90917 --query 'NetworkInterfaces[].NetworkInterfaceId'
   aws ec2 delete-security-group --group-id sg-06060062ed0b90917
   ```

   The first query must print `[]`; if it does not, stop.

3. **Plan and read it.** Expected, on this account's first apply: 35 to
   import; 13 to add (the egress-only gateway, two IPv6 routes, nine IPv6
   security-group rules, the DLM policy); in-place updates for the IPv6
   blocks, the tags, the rule descriptions, and the default group's egress
   rule; **0 to destroy, 0 to replace**. The default route table is imported
   by the VPC ID, which is how that resource identifies itself; the reverse
   record carries its trailing dot; the key policy carries the `Id` the
   account already holds, so neither shows a change.

   ```sh
   tofu init
   tofu plan -out tf.plan
   tofu show tf.plan | grep -E "^Plan:|must be replaced|will be destroyed"
   ```

4. **Apply, then prove nothing moved:**

   ```sh
   tofu apply tf.plan
   tofu plan -detailed-exitcode; echo "plan exit: $?"
   aws ec2 describe-vpcs --vpc-ids "$(tofu output -raw vpc_id)" --query 'Vpcs[0].Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlockState.State'
   aws ec2 describe-volumes --volume-ids $(tofu output -json data_volume_ids | jq -r '.[]') --query 'Volumes[].Attachments[].State'
   aws ec2 describe-addresses --allocation-ids "$(tofu output -raw eip_allocation_id)" --query 'Addresses[0].AssociationId'
   aws dlm get-lifecycle-policies --query 'Policies[].State'
   ```

   The volumes stay `attached`, the address stays associated, and the first
   DLM snapshot appears after 06:00 Coordinated Universal Time (UTC) the next
   day.

5. **Afterwards:** delete `imports.tf` and commit; the list below keeps the
   identifiers. On this account the first apply stopped at the IPv6 egress
   rule, which AWS had already created when the VPC gained its block; an
   `import` block for that rule and a second apply (1 imported, 2 changed)
   finished the adoption.

## What was imported

| Resource | Identifier |
|---|---|
| `aws_vpc.this` | `vpc-0a8f8c901d76ddc0a` |
| `aws_subnet.public["a"]`, `["b"]`, `["c"]` | `subnet-0d8509b64041b4a04`, `subnet-081a3d5827a970a05`, `subnet-0d3e43fa9bdc13099` |
| `aws_subnet.private["a"]`, `["b"]`, `["c"]` | `subnet-0d2143d3700e01544`, `subnet-03bd8226e9992b8a9`, `subnet-0eab8531e16d74a3a` |
| `aws_internet_gateway.this` | `igw-098e216bbd4aaaa3c` |
| `aws_route_table.public`, its default route, and three associations | `rtb-0fcd295e0d46426c2` |
| `aws_default_route_table.private` | `vpc-0a8f8c901d76ddc0a` (the VPC; the table is `rtb-06bacf40792e5d15d`) |
| `aws_security_group.instance` and its 13 rules, plus the IPv6 egress rule AWS added | `sg-06944d97f3ccd432c`, rule IDs from `describe-security-group-rules` |
| `aws_default_security_group.this` | `sg-00db20189e9817986` |
| `aws_kms_key.persephone`, `aws_kms_alias.persephone` | `ac75f350-ad25-479c-99e2-d9bb78e3e1bf`, `alias/persephone-kms-key` |
| `aws_eip.persephone`, `aws_eip_domain_name.persephone` | `eipalloc-08226c5c3ed6579f4` |
| `aws_ebs_volume.data["home"]`, `["web"]` | `vol-00120fb20ff72e79c`, `vol-0bf39b92006003b08` |

## Not managed here

The default network access control list and Dynamic Host Configuration
Protocol (DHCP) option set stay as AWS
created them. The three key pairs stay until the rebuild decides which one
survives. The manual snapshot set taken before the migration is outside the
DLM policy and is deleted by hand when the migration is complete. The
instance, its root volume, the volume attachments, and the EIP association
are `30-hosts/persephone`.

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
| [aws_default_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_dlm_lifecycle_policy.daily](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dlm_lifecycle_policy) | resource |
| [aws_ebs_volume.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_egress_only_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/egress_only_internet_gateway) | resource |
| [aws_eip.persephone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_eip_domain_name.persephone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_domain_name) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_alias.persephone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.persephone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route.private_ipv6_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_ipv4_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_ipv6_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_security_group_egress_rule.all_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.all_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.icmp_echo_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.icmp_echo_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.public_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.public_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.ssh_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.persephone_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [terraform_remote_state.account](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_region"></a> [region](#input\_region) | Region the platform lives in; the hosts' stacks read it from this stack's outputs. | `string` | `"us-east-1"` | no |
| <a name="input_snapshot_retention_count"></a> [snapshot\_retention\_count](#input\_snapshot\_retention\_count) | Daily snapshots Data Lifecycle Manager keeps per volume. | `number` | `7` | no |
| <a name="input_ssh_source_cidrs"></a> [ssh\_source\_cidrs](#input\_ssh\_source\_cidrs) | IPv4 ranges allowed to reach port 22: the home Internet service provider's blocks. Narrowed to the Tailscale network once every host is in the tailnet. | `list(string)` | <pre>[<br/>  "47.182.0.0/15",<br/>  "47.184.0.0/14",<br/>  "47.188.0.0/15",<br/>  "47.190.0.0/16"<br/>]</pre> | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | Bucket that stores OpenTofu state, from 00-bootstrap; this stack reads 10-account's outputs from it. | `string` | `"cybris-net-tf-bucket"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_data_volume_ids"></a> [data\_volume\_ids](#output\_data\_volume\_ids) | Data volume IDs by role; 30-hosts attaches them. |
| <a name="output_eip_allocation_id"></a> [eip\_allocation\_id](#output\_eip\_allocation\_id) | Allocation ID of the public address; 30-hosts associates it. |
| <a name="output_eip_public_ip"></a> [eip\_public\_ip](#output\_eip\_public\_ip) | The public address of the DNS, NTP, and web services. |
| <a name="output_instance_security_group_id"></a> [instance\_security\_group\_id](#output\_instance\_security\_group\_id) | The security group the hosts attach. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | The key that encrypts every volume. |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnet IDs by availability-zone letter. |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | Public subnet IDs by availability-zone letter. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The VPC every host lives in. |
| <a name="output_vpc_ipv6_cidr_block"></a> [vpc\_ipv6\_cidr\_block](#output\_vpc\_ipv6\_cidr\_block) | The Amazon-provided IPv6 /56 of the VPC. |
<!-- END_TF_DOCS -->
