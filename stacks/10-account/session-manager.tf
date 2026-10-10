# Systems Manager Session Manager preferences for the account (this region).
# Sessions on persephone run as ssm-user, which has passwordless root, so every
# session's transcript goes to the logs bucket under session-manager/, encrypted
# with the bucket's own AES256 and expired with the other logs, and the session
# stream itself is encrypted with a key of its own on top of TLS. Decided
# 2026-10-10. The document name is fixed by AWS; opening the Session Manager
# preferences in the console before the first apply creates it, and the apply
# would then have to import it.
# The key that encrypts the Session Manager stream between the person and the
# agent. Its policy only delegates to IAM, like the platform key's.
data "aws_iam_policy_document" "session_manager_key" {
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
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "session_manager" {
  description             = "Systems Manager Session Manager session encryption"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.session_manager_key.json

  tags = {
    Name = "Session Manager KMS Key"
  }
}

resource "aws_kms_alias" "session_manager" {
  name          = "alias/session-manager"
  target_key_id = aws_kms_key.session_manager.key_id
}

resource "aws_ssm_document" "session_preferences" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: transcripts to the logs bucket."
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.logs.id
      s3KeyPrefix                 = "session-manager"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = ""
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = false
      kmsKeyId                    = aws_kms_key.session_manager.arn
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = ""
      shellProfile = {
        linux   = ""
        windows = ""
      }
    }
  })
}

# The agent on the instance writes the transcript with the instance role, so
# the role may write only under session-manager/ and read the bucket's
# encryption setting, which the agent checks before it uploads, and decrypt
# with the session key. People who start sessions get kms:GenerateDataKey
# through their permission sets, because the key policy delegates to IAM.
data "aws_iam_policy_document" "ec2_persephone_session_logs" {
  statement {
    sid       = "WriteSessionTranscripts"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/session-manager/*"]
  }

  statement {
    sid       = "ReadBucketEncryption"
    effect    = "Allow"
    actions   = ["s3:GetEncryptionConfiguration"]
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid       = "DecryptSessionStream"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.session_manager.arn]
  }
}

resource "aws_iam_role_policy" "ec2_persephone_session_logs" {
  name   = "session-manager-transcripts"
  role   = aws_iam_role.ec2_persephone.id
  policy = data.aws_iam_policy_document.ec2_persephone_session_logs.json
}
