resource "aws_account_alternate_contact" "this" {
  for_each = toset(["SECURITY", "BILLING", "OPERATIONS"])

  alternate_contact_type = each.value
  name                   = var.contact_name
  title                  = var.contact_title
  email_address          = var.alert_email
  phone_number           = var.contact_phone
}

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 26
  require_symbols                = false
  require_numbers                = false
  require_uppercase_characters   = false
  require_lowercase_characters   = false
  allow_users_to_change_password = true
  password_reuse_prevention      = 10
  hard_expiry                    = false
  max_password_age               = 0
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# The default key is set by 20-platform, beside the key. Forgotten here, not
# destroyed: destroying it resets the default to the AWS-managed key.
removed {
  from = aws_ebs_default_kms_key.this

  lifecycle {
    destroy = false
  }
}
