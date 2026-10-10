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

# Instance roles are named ec2-* so EngineerLead and the CI apply role can pass
# them to EC2 (PassOnlyInstanceRoles) without being able to create them.
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# persephone: Systems Manager Session Manager only. The host calls no other
# AWS API, so the role carries the managed core policy and nothing else.
resource "aws_iam_role" "ec2_persephone" {
  name               = "ec2-persephone"
  description        = "persephone.cybris.net instance role: Systems Manager Session Manager (AmazonSSMManagedInstanceCore) only."
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ec2_persephone_ssm" {
  role       = aws_iam_role.ec2_persephone.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_persephone" {
  name = "ec2-persephone"
  role = aws_iam_role.ec2_persephone.name
}
