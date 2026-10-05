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

# New volumes default to the one key this account keeps; the other three are
# scheduled for deletion by hand once nothing references them. Not imported:
# the setting is replaced whenever its key changes, so it is simply set.
resource "aws_ebs_default_kms_key" "this" {
  key_arn = data.aws_kms_alias.persephone.target_key_arn
}
