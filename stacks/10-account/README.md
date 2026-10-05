# 10-account

The account's identity, audit, and alerting baseline: Identity and Access
Management (IAM) Identity Center groups, permission sets, and assignments;
the OpenID Connect (OIDC) provider and the roles GitHub Actions assumes;
the role Data Lifecycle Manager (DLM) assumes for the snapshot policy in
`20-platform`;
CloudTrail; GuardDuty; Amazon Web Services (AWS) Config (adopted); IAM Access Analyzer; the Simple
Notification Service (SNS) topic that budget and GuardDuty alerts publish to;
the cost budget (adopted); the alternate contacts; the password policy
(adopted); and the Elastic Block Store (EBS) encryption defaults (adopted).

Applied from a workstation with the administrator profile, never from
continuous integration (CI). State: `aws-cybris-net/10-account.tfstate`.
First applied 2026-10-05 (17 imported, 67 added, 5 changed, 0 destroyed);
the `import` blocks were removed once the state held the adopted resources.

## Permission sets

| Set | Group | Managed policy | Added | Session |
|---|---|---|---|---|
| AdministratorAccess | administrators | AdministratorAccess | guard rails | 1 h |
| EngineerLead | engineers | PowerUserAccess | `EngineerLead` customer-managed policy (role reads, `PassRole` on `ec2-*` and on the `dlm-snapshots` role, no state-version deletion, no Identity Center writes), guard rails | 8 h |
| ReadOnly | read-only | ReadOnlyAccess | guard rails | 8 h |
| BillingAccess | billing | job-function/Billing | guard rails | 4 h |

The guard rails are one inline policy on every set: allow the two `signin`
actions the AWS MCP connector needs to open a session (nothing short of
AdministratorAccess grants them); deny every request
outside the allowed regions (`us-east-1`, `us-east-2`, `us-west-2`, chosen
for a later high-availability design) except to global services; deny stopping or deleting
CloudTrail, GuardDuty, Config, and Access Analyzer; deny terminating or
deleting anything tagged `Protected = true` (instances, volumes, addresses,
Virtual Private Clouds (VPCs), Key Management Service (KMS) keys); deny deleting the state and log buckets; deny leaving the
organization or closing the account. An administrator who needs one of those
actions edits this stack, which is the point.

## Secrets and personal data

`op.env` (ignored by git; copy `op.env.example`) supplies the administrator's
Identity Center user name, the alert address, and the alternate contacts'
name, title, and phone number through 1Password references. None of these
appear in code or state outputs.

## First apply: the order matters (done 2026-10-05; kept for a new account)

Every command runs from this directory with `AWS_PROFILE=cybris` exported and
`op.env` in place; `tofu` is the 1Password wrapper from the repository README.

1. **Detach the seven redundant managed policies** from the existing
   `AdministratorAccess` permission set, so the plan adopts it without a
   change it cannot express. Then provision the set so the account sees it.

   ```sh
   instance=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
   set=$(aws sso-admin list-permission-sets --instance-arn "$instance" --query 'PermissionSets[0]' --output text)
   for policy in \
     arn:aws:iam::aws:policy/AWSAccountManagementFullAccess \
     arn:aws:iam::aws:policy/AWSBillingConductorFullAccess \
     arn:aws:iam::aws:policy/AWSConfigUserAccess \
     arn:aws:iam::aws:policy/CostOptimizationHubAdminAccess \
     arn:aws:iam::aws:policy/job-function/Billing \
     arn:aws:iam::aws:policy/service-role/AWSCostAndUsageReportAutomationPolicy \
     arn:aws:iam::aws:policy/service-role/AWS_ConfigRole; do
     aws sso-admin detach-managed-policy-from-permission-set --instance-arn "$instance" --permission-set-arn "$set" --managed-policy-arn "$policy"
   done
   aws sso-admin provision-permission-set --instance-arn "$instance" --permission-set-arn "$set" --target-type ALL_PROVISIONED_ACCOUNTS
   ```

2. **Delete the default VPCs** in every region before the region deny
   exists, because afterwards no permission set can reach the regions
   outside the allowed three.
   `sh ../../scripts/delete-default-vpcs.sh` lists them; `--apply` deletes
   those with no network interface attached. (The 16 on this account went
   on 2026-10-05.)

3. **Plan and read it.** Expected, on this account's first apply: 17 to import; adds for everything new
   (groups, permission sets, policies, OIDC, CloudTrail and its bucket,
   GuardDuty, Access Analyzer, SNS, alternate contacts, lifecycle rules);
   in-place updates for the administrator set's session length, the Config
   bucket's default encryption (KMS to Simple Storage Service (S3)-managed keys, SSE-S3), tags, and the EBS default
   key; **0 to destroy, 0 to replace**.

   ```sh
   tofu init
   tofu plan -out tf.plan
   tofu show tf.plan
   ```

4. **Apply**, then confirm the SNS subscription from the mail it sends, sign
   out and in again so the new session length applies, and check:

   ```sh
   tofu apply tf.plan
   aws sso logout && aws sso login --profile cybris
   aws cloudtrail get-trail-status --name account --query IsLogging
   aws guardduty list-detectors
   aws guardduty list-detectors --region us-east-2
   aws guardduty list-detectors --region us-west-2
   aws accessanalyzer list-analyzers --query 'analyzers[].status'
   aws sns list-subscriptions-by-topic --topic-arn "$(tofu output -raw account_alerts_topic_arn)" --query 'Subscriptions[].SubscriptionArn'
   ```

5. **Afterwards, by hand and in this order:** switch the old repositories'
   credentials path off (`tf-cybris-user`'s keys, group, and the unused
   `AdministratorAccess` IAM role, one week apart per key); schedule deletion
   of the three KMS keys nothing references any more
   (`terraform-s3-encryption-key`, `cybris-aws-config-key`,
   `cybris-default-ebs-encryption-key`, 30-day window); disable Security Hub
   once GuardDuty has produced its first findings.

## Not managed here

The 25 Config rules created by hand stay as they are; a conformance pack
replaces them in a later change. Security Hub is disabled by hand rather
than destroyed by code. The CI apply role arrives with the Apply workflow.

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
| <a name="provider_aws.us_east_2"></a> [aws.us\_east\_2](#provider\_aws.us\_east\_2) | 6.67.0 |
| <a name="provider_aws.us_west_2"></a> [aws.us\_west\_2](#provider\_aws.us\_west\_2) | 6.67.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_accessanalyzer_analyzer.account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_account_alternate_contact.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/account_alternate_contact) | resource |
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_cloudtrail.account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) | resource |
| [aws_cloudwatch_event_rule.guardduty_findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.guardduty_findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_config_configuration_recorder.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder) | resource |
| [aws_config_configuration_recorder_status.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder_status) | resource |
| [aws_config_delivery_channel.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_delivery_channel) | resource |
| [aws_ebs_default_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_default_kms_key) | resource |
| [aws_ebs_encryption_by_default.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_encryption_by_default) | resource |
| [aws_guardduty_detector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector) | resource |
| [aws_guardduty_detector.us_east_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector) | resource |
| [aws_guardduty_detector.us_west_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector) | resource |
| [aws_guardduty_detector_feature.disabled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_guardduty_detector_feature.us_east_2_disabled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_guardduty_detector_feature.us_west_2_disabled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_iam_account_password_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_account_password_policy) | resource |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.engineer_lead](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.dlm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.gha_aws_cybris_net_plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.gha_freebsd_cloud_img_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.gha_aws_cybris_net_plan_state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.gha_freebsd_cloud_img_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.dlm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.gha_aws_cybris_net_plan_read_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_identitystore_group.administrators](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group.billing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group.engineers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group.read_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group_membership.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group_membership) | resource |
| [aws_s3_bucket.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_sns_topic.account_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.account_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.account_alerts_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_ssoadmin_account_assignment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_customer_managed_policy_attachment.engineer_lead](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_customer_managed_policy_attachment) | resource |
| [aws_ssoadmin_managed_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.administrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set.billing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set.engineer_lead](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set.read_only](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set_inline_policy.guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set_inline_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.account_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.config_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dlm_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.engineer_lead](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.freebsd_images_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.github_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.logs_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.state_plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_identitystore_user.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_user) | data source |
| [aws_kms_alias.persephone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_user_name"></a> [admin\_user\_name](#input\_admin\_user\_name) | The administrator's Identity Center user name, exactly as typed on the start page (not an email, not a role ARN); supplied by op.env, never committed. | `string` | n/a | yes |
| <a name="input_alert_email"></a> [alert\_email](#input\_alert\_email) | Address that receives budget, GuardDuty, and alternate-contact mail; supplied by op.env. | `string` | n/a | yes |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions the permission sets may act in; every other region is denied. GuardDuty watches each of them. | `list(string)` | <pre>[<br/>  "us-east-1",<br/>  "us-east-2",<br/>  "us-west-2"<br/>]</pre> | no |
| <a name="input_budget_limit_usd"></a> [budget\_limit\_usd](#input\_budget\_limit\_usd) | Monthly cost budget in USD. | `number` | `70` | no |
| <a name="input_contact_name"></a> [contact\_name](#input\_contact\_name) | Name for the security, billing, and operations alternate contacts; supplied by op.env. | `string` | n/a | yes |
| <a name="input_contact_phone"></a> [contact\_phone](#input\_contact\_phone) | Phone number for the alternate contacts, international format; supplied by op.env. | `string` | n/a | yes |
| <a name="input_contact_title"></a> [contact\_title](#input\_contact\_title) | Title for the alternate contacts; supplied by op.env. | `string` | n/a | yes |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | GitHub organisation whose repositories may assume the OIDC roles. | `string` | `"cdf-eagles"` | no |
| <a name="input_github_owner_id"></a> [github\_owner\_id](#input\_github\_owner\_id) | Numeric ID of the GitHub owner; GitHub embeds it in the OpenID Connect subject of repositories created after 2026-07-15 (`repo:<owner>@<id>/<repository>@<id>:...`). | `number` | `59536280` | no |
| <a name="input_github_repository_ids"></a> [github\_repository\_ids](#input\_github\_repository\_ids) | Numeric IDs of the repositories that assume the OIDC roles, by name; part of the subject for repositories on the immutable format. | `map(number)` | <pre>{<br/>  "aws-cybris-net": 1404901186,<br/>  "freebsd-cloud-img": 1129794967<br/>}</pre> | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Days CloudTrail and Config objects are kept before they expire. | `number` | `400` | no |
| <a name="input_region"></a> [region](#input\_region) | Home region: where the single-region resources of this stack live. | `string` | `"us-east-1"` | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | Bucket that stores OpenTofu state, from 00-bootstrap. | `string` | `"cybris-net-tf-bucket"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_alerts_topic_arn"></a> [account\_alerts\_topic\_arn](#output\_account\_alerts\_topic\_arn) | SNS topic that budget and GuardDuty alerts publish to. |
| <a name="output_dlm_role_arn"></a> [dlm\_role\_arn](#output\_dlm\_role\_arn) | Role that Data Lifecycle Manager assumes for the snapshot policy in 20-platform. |
| <a name="output_engineer_lead_policy_arn"></a> [engineer\_lead\_policy\_arn](#output\_engineer\_lead\_policy\_arn) | Customer-managed policy shared by the EngineerLead permission set and the CI apply role. |
| <a name="output_gha_aws_cybris_net_plan_role_arn"></a> [gha\_aws\_cybris\_net\_plan\_role\_arn](#output\_gha\_aws\_cybris\_net\_plan\_role\_arn) | Role the aws-cybris-net Plan workflow assumes through OIDC. |
| <a name="output_gha_freebsd_cloud_img_publish_role_arn"></a> [gha\_freebsd\_cloud\_img\_publish\_role\_arn](#output\_gha\_freebsd\_cloud\_img\_publish\_role\_arn) | Role the freebsd-cloud-img publish jobs assume through OIDC. |
| <a name="output_logs_bucket_name"></a> [logs\_bucket\_name](#output\_logs\_bucket\_name) | Bucket that holds the CloudTrail logs. |
| <a name="output_permission_set_arns"></a> [permission\_set\_arns](#output\_permission\_set\_arns) | Permission set ARNs by key, for the plan and apply workflows' documentation. |
<!-- END_TF_DOCS -->
