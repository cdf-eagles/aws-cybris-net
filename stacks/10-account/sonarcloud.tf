# One SonarCloud user token serves the CI analyses of the public repositories
# in local.sonarcloud_repositories (organization tokens need a paid plan, and
# SonarCloud accepts no GitHub App credential). It is a SecureString standard
# parameter under the AWS-managed aws/ssm key, which costs nothing at this
# volume. The value comes from 1Password through op.env and is written with a
# write-only attribute, so it never reaches the plan or the state.
resource "aws_ssm_parameter" "sonarcloud_token" {
  #checkov:skip=CKV_AWS_337:The AWS-managed aws/ssm key is the chosen default; a customer-managed key costs more each month than one CI token is worth.
  name             = local.sonarcloud_token_name
  description      = "SonarCloud user token for the CI analyses; gha-sonarcloud-scan reads it."
  type             = "SecureString"
  tier             = "Standard"
  value_wo         = var.sonarcloud_token
  value_wo_version = local.sonarcloud_token_version
}

resource "aws_iam_role" "gha_sonarcloud_scan" {
  name                 = "gha-sonarcloud-scan"
  description          = "GitHub Actions in the SonarCloud-analysed repositories, pull requests and the main branch: read the SonarCloud token."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["sonarcloud_scan"].json
  max_session_duration = 3600
}

# The aws/ssm key policy lets every principal in the account decrypt through
# Systems Manager, so reading the parameter needs no KMS permission here.
data "aws_iam_policy_document" "sonarcloud_token_read" {
  statement {
    sid       = "ReadSonarCloudToken"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sonarcloud_token.arn]
  }
}

resource "aws_iam_role_policy" "gha_sonarcloud_scan" {
  name   = "read-sonarcloud-token"
  role   = aws_iam_role.gha_sonarcloud_scan.id
  policy = data.aws_iam_policy_document.sonarcloud_token_read.json
}

# ReadOnlyAccess allows every parameter read, and the aws/ssm key policy then
# decrypts for any principal in the account. The ReadOnly permission set and the
# Plan role never need the token, so both are refused the decryption, whichever
# read action asks for it: Systems Manager names the parameter in the
# encryption context.
data "aws_iam_policy_document" "deny_sonarcloud_token_decrypt" {
  statement {
    sid       = "DenyDecryptingTheSonarCloudToken"
    effect    = "Deny"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = [aws_ssm_parameter.sonarcloud_token.arn]
    }
  }
}

data "aws_iam_policy_document" "read_only" {
  source_policy_documents = [
    data.aws_iam_policy_document.guardrails.json,
    data.aws_iam_policy_document.deny_sonarcloud_token_decrypt.json,
  ]
}

resource "aws_iam_role_policy" "gha_aws_cybris_net_plan_deny_sonarcloud_token" {
  name   = "deny-sonarcloud-token"
  role   = aws_iam_role.gha_aws_cybris_net_plan.id
  policy = data.aws_iam_policy_document.deny_sonarcloud_token_decrypt.json
}
