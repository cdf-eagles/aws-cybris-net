# The account's one customer-managed key: it encrypts every volume and is the
# EBS default (set in 10-account).
data "aws_iam_policy_document" "persephone_key" {
  #checkov:skip=CKV_AWS_109:a key policy names its own key as * and must grant the account root kms:*
  #checkov:skip=CKV_AWS_111:a key policy names its own key as * and must grant the account root kms:*
  #checkov:skip=CKV_AWS_356:a key policy names its own key as * and must grant the account root kms:*
  policy_id = "key-default-1"

  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "persephone" {
  description             = "persephone.cybris.net KMS Key"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  policy                  = data.aws_iam_policy_document.persephone_key.json

  tags = {
    Name      = "persephone.cybris.net KMS Key"
    Protected = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "persephone" {
  name          = "alias/persephone-kms-key"
  target_key_id = aws_kms_key.persephone.key_id
}
