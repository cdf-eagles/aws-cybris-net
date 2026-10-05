resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_oidc_issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  for_each = {
    freebsd_cloud_img_publish = "repo:${var.github_owner}/freebsd-cloud-img:ref:refs/heads/main"
    aws_cybris_net_plan       = "repo:${var.github_owner}/aws-cybris-net:pull_request"
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_issuer}:sub"
      values   = [each.value]
    }
  }
}

# freebsd-cloud-img publishes its images and web page with `aws s3 sync`.
resource "aws_iam_role" "gha_freebsd_cloud_img_publish" {
  name                 = "gha-freebsd-cloud-img-publish"
  description          = "GitHub Actions in freebsd-cloud-img, main branch only: publish to the freebsd-images bucket."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["freebsd_cloud_img_publish"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "freebsd_images_publish" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::freebsd-images"]
  }

  statement {
    sid    = "WriteObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::freebsd-images/*"]
  }
}

resource "aws_iam_role_policy" "gha_freebsd_cloud_img_publish" {
  name   = "publish-freebsd-images"
  role   = aws_iam_role.gha_freebsd_cloud_img_publish.id
  policy = data.aws_iam_policy_document.freebsd_images_publish.json
}

# aws-cybris-net plans pull requests: read everything, hold the state lock.
resource "aws_iam_role" "gha_aws_cybris_net_plan" {
  name                 = "gha-aws-cybris-net-plan"
  description          = "GitHub Actions in aws-cybris-net, pull requests only: tofu plan."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["aws_cybris_net_plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "gha_aws_cybris_net_plan_read_only" {
  role       = aws_iam_role.gha_aws_cybris_net_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_plan" {
  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
  }

  statement {
    sid       = "HoldStateLock"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/aws-cybris-net/*.tflock"]
  }
}

resource "aws_iam_role_policy" "gha_aws_cybris_net_plan_state" {
  name   = "read-state-and-lock"
  role   = aws_iam_role.gha_aws_cybris_net_plan.id
  policy = data.aws_iam_policy_document.state_plan.json
}
