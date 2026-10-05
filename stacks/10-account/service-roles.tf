# Roles that AWS services assume on the account's behalf. They live here
# because IAM is this stack's, and the stacks that use them only pass them.

data "aws_iam_policy_document" "dlm_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

# Data Lifecycle Manager takes and expires the daily volume snapshots that
# 20-platform schedules.
resource "aws_iam_role" "dlm" {
  name               = "dlm-snapshots"
  description        = "Data Lifecycle Manager: create, tag, and delete the scheduled volume snapshots."
  assume_role_policy = data.aws_iam_policy_document.dlm_trust.json
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}
