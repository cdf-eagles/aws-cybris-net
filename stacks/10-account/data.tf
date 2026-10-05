data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_ssoadmin_instances" "this" {}

data "aws_identitystore_user" "admin" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.admin_user_name
    }
  }
}

data "aws_kms_alias" "persephone" {
  name = "alias/persephone-kms-key"
}
