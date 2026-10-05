# Guard rails every permission set carries, in place of the service control
# policies that cannot apply to an organization's management account.
data "aws_iam_policy_document" "guardrails" {
  statement {
    sid         = "DenyOutsideHomeRegion"
    effect      = "Deny"
    not_actions = [for s in local.global_services : "${s}:*"]
    resources   = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  statement {
    sid    = "DenyDisablingAuditTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromAdministratorAccount",
      "config:DeleteConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "access-analyzer:DeleteAnalyzer",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyDestroyingProtectedResources"
    effect = "Deny"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteVolume",
      "ec2:ReleaseAddress",
      "ec2:DeleteVpc",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Protected"
      values   = ["true"]
    }
  }

  statement {
    sid     = "DenyDeletingStateAndLogBuckets"
    effect  = "Deny"
    actions = ["s3:DeleteBucket"]
    resources = [
      local.state_bucket_arn,
      aws_s3_bucket.logs.arn,
    ]
  }

  statement {
    sid    = "DenyLeavingTheAccount"
    effect = "Deny"
    actions = [
      "organizations:LeaveOrganization",
      "account:CloseAccount",
    ]
    resources = ["*"]
  }
}

# What EngineerLead has beyond PowerUserAccess, and what it must not do to the
# state bucket. Shared with the CI apply role as a customer-managed policy.
data "aws_iam_policy_document" "engineer_lead" {
  #checkov:skip=CKV_AWS_356:listing roles, policies, and providers is account-wide
  statement {
    sid    = "ReadRolesForInstanceProfiles"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:ListRoles",
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListInstanceProfiles",
      "iam:ListInstanceProfilesForRole",
      "iam:GetInstanceProfile",
      "iam:ListOpenIDConnectProviders",
      "iam:GetOpenIDConnectProvider",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassOnlyInstanceRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/ec2-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "KeepStateHistory"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${local.state_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "engineer_lead" {
  name        = "EngineerLead"
  path        = "/"
  description = "Additions to PowerUserAccess for the EngineerLead permission set and the CI apply role."
  policy      = data.aws_iam_policy_document.engineer_lead.json
}
