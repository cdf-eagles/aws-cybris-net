# One snapshot a day of every volume tagged Backup = daily, kept a week. The
# role comes from 10-account; EngineerLead may pass it to DLM and nothing else.
resource "aws_dlm_lifecycle_policy" "daily" {
  description        = "Daily snapshots of volumes tagged Backup daily"
  execution_role_arn = data.terraform_remote_state.account.outputs.dlm_role_arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      Backup = "daily"
    }

    schedule {
      name      = "daily"
      copy_tags = true

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["06:00"]
      }

      retain_rule {
        count = var.snapshot_retention_count
      }

      tags_to_add = {
        Purpose = "dlm"
      }
    }
  }

  tags = {
    Name = "Daily volume snapshots"
  }
}
