# restic backups of soundwave.sleem.net. The bucket keeps no expiry on current
# objects: restic prunes its own repository, and a deleted pack stays
# recoverable as a noncurrent version for 30 days.
resource "aws_s3_bucket" "restic_soundwave" {
  bucket = "cybris-soundwave-restic"

  tags = {
    Name      = "Restic backups of soundwave"
    Backup    = "soundwave-restic"
    Protected = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "restic_soundwave" {
  bucket = aws_s3_bucket.restic_soundwave.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "restic_soundwave" {
  bucket = aws_s3_bucket.restic_soundwave.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "restic_soundwave" {
  bucket = aws_s3_bucket.restic_soundwave.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "restic_soundwave" {
  bucket = aws_s3_bucket.restic_soundwave.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled       = true
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "restic_soundwave" {
  bucket = aws_s3_bucket.restic_soundwave.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.restic_soundwave]
}

data "aws_iam_policy_document" "restic_soundwave_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.restic_soundwave.arn,
      "${aws_s3_bucket.restic_soundwave.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "restic_soundwave" {
  bucket = aws_s3_bucket.restic_soundwave.id
  policy = data.aws_iam_policy_document.restic_soundwave_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.restic_soundwave]
}

data "aws_iam_policy_document" "restic_backup" {
  statement {
    sid    = "ListResticBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.restic_soundwave.arn]
  }

  statement {
    sid    = "ReadWriteResticObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.restic_soundwave.arn}/*"]
  }

  # The allows above already exclude these; the deny keeps a later allow from
  # letting a stolen key erase version history or loosen the bucket.
  statement {
    sid    = "DenyHistoryAndBucketChanges"
    effect = "Deny"
    actions = [
      "s3:DeleteObjectVersion",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
    ]
    resources = [
      aws_s3_bucket.restic_soundwave.arn,
      "${aws_s3_bucket.restic_soundwave.arn}/*",
    ]
  }
}

resource "aws_iam_group" "restic_backup" {
  name = "restic-backup"
}

resource "aws_iam_group_policy" "restic_backup" {
  name   = "restic-backup"
  group  = aws_iam_group.restic_backup.name
  policy = data.aws_iam_policy_document.restic_backup.json
}

# The one IAM user in the account, an exception decided 2026-10-30. Its access
# key is created outside OpenTofu so that it never reaches state.
resource "aws_iam_user" "restic_soundwave" {
  #checkov:skip=CKV_AWS_273:restic on soundwave cannot use Identity Center; an access key exception decided 2026-10-30
  name = "restic-soundwave"
  path = "/service/"
}

resource "aws_iam_user_group_membership" "restic_soundwave" {
  user   = aws_iam_user.restic_soundwave.name
  groups = [aws_iam_group.restic_backup.name]
}
