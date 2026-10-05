# Groups: one per permission set. The administrator is a member of all four.
resource "aws_identitystore_group" "administrators" {
  identity_store_id = local.identity_store_id
  display_name      = "administrators"
  description       = "Full access, one-hour sessions, break-glass and the bootstrap and account stacks."
}

resource "aws_identitystore_group" "engineers" {
  identity_store_id = local.identity_store_id
  display_name      = "engineers"
  description       = "Builds and changes infrastructure; no identity, organization, or billing rights."
}

resource "aws_identitystore_group" "read_only" {
  identity_store_id = local.identity_store_id
  display_name      = "read-only"
  description       = "Reads everything, changes nothing."
}

resource "aws_identitystore_group" "billing" {
  identity_store_id = local.identity_store_id
  display_name      = "billing"
  description       = "Invoices, Cost Explorer, and budgets."
}

resource "aws_identitystore_group_membership" "admin" {
  for_each = {
    administrators = aws_identitystore_group.administrators.group_id
    engineers      = aws_identitystore_group.engineers.group_id
    read_only      = aws_identitystore_group.read_only.group_id
    billing        = aws_identitystore_group.billing.group_id
  }

  identity_store_id = local.identity_store_id
  group_id          = each.value
  member_id         = data.aws_identitystore_user.admin.user_id
}

# Permission sets.
resource "aws_ssoadmin_permission_set" "administrator" {
  instance_arn     = local.sso_instance_arn
  name             = "AdministratorAccess"
  description      = "Administrator Access"
  session_duration = "PT1H"
}

resource "aws_ssoadmin_permission_set" "engineer_lead" {
  instance_arn     = local.sso_instance_arn
  name             = "EngineerLead"
  description      = "PowerUserAccess plus instance-role pass-through; no IAM, Organizations, Account, or billing."
  session_duration = "PT8H"
}

resource "aws_ssoadmin_permission_set" "read_only" {
  instance_arn     = local.sso_instance_arn
  name             = "ReadOnly"
  description      = "ReadOnlyAccess with the account guard rails."
  session_duration = "PT8H"
}

resource "aws_ssoadmin_permission_set" "billing" {
  instance_arn     = local.sso_instance_arn
  name             = "BillingAccess"
  description      = "The Billing job function with the account guard rails."
  session_duration = "PT4H"
}

locals {
  permission_sets = {
    administrator = aws_ssoadmin_permission_set.administrator.arn
    engineer_lead = aws_ssoadmin_permission_set.engineer_lead.arn
    read_only     = aws_ssoadmin_permission_set.read_only.arn
    billing       = aws_ssoadmin_permission_set.billing.arn
  }

  managed_policies = {
    administrator = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
    engineer_lead = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
    read_only     = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
    billing       = "arn:${data.aws_partition.current.partition}:iam::aws:policy/job-function/Billing"
  }

  group_ids = {
    administrator = aws_identitystore_group.administrators.group_id
    engineer_lead = aws_identitystore_group.engineers.group_id
    read_only     = aws_identitystore_group.read_only.group_id
    billing       = aws_identitystore_group.billing.group_id
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.permission_sets

  instance_arn       = local.sso_instance_arn
  permission_set_arn = each.value
  managed_policy_arn = local.managed_policies[each.key]
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "engineer_lead" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.engineer_lead.arn

  customer_managed_policy_reference {
    name = aws_iam_policy.engineer_lead.name
    path = aws_iam_policy.engineer_lead.path
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "guardrails" {
  for_each = local.permission_sets

  instance_arn       = local.sso_instance_arn
  permission_set_arn = each.value
  inline_policy      = data.aws_iam_policy_document.guardrails.json
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.permission_sets

  instance_arn       = local.sso_instance_arn
  permission_set_arn = each.value
  principal_id       = local.group_ids[each.key]
  principal_type     = "GROUP"
  target_id          = local.account_id
  target_type        = "AWS_ACCOUNT"

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.this,
    aws_ssoadmin_customer_managed_policy_attachment.engineer_lead,
    aws_ssoadmin_permission_set_inline_policy.guardrails,
  ]
}
