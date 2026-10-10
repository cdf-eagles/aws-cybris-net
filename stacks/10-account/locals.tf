locals {
  default_tags = {
    Project     = "cybris.net"
    Environment = "production"
    Owner       = "infrastructure"
    ManagedBy   = "opentofu"
    Repository  = "aws-cybris-net"
    Stack       = "10-account"
  }

  account_id         = data.aws_caller_identity.current.account_id
  sso_instance_arn   = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id  = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  state_bucket_arn   = "arn:aws:s3:::${var.state_bucket_name}"
  github_oidc_issuer = "token.actions.githubusercontent.com"

  guardduty_disabled_features = [
    "S3_DATA_EVENTS",
    "EKS_AUDIT_LOGS",
    "EBS_MALWARE_PROTECTION",
    "LAMBDA_NETWORK_LOGS",
    "RUNTIME_MONITORING",
  ]

  # Sub-features GuardDuty reports under RUNTIME_MONITORING; declared so a plan
  # does not keep offering to remove what the service always returns.
  guardduty_runtime_sub_features = [
    "EC2_AGENT_MANAGEMENT",
    "ECS_FARGATE_AGENT_MANAGEMENT",
    "EKS_ADDON_MANAGEMENT",
  ]

  # Services whose requests carry no region, or whose only region is us-east-1,
  # exempted from the region deny so that global consoles and billing keep working.
  global_services = [
    "iam", "sts", "organizations", "account", "sso", "sso-directory", "identitystore",
    "budgets", "ce", "cur", "billing", "invoicing", "payments", "consolidatedbilling",
    "freetier", "tax", "savingsplans", "cost-optimization-hub", "pricing",
    "route53", "route53domains", "cloudfront", "shield", "globalaccelerator", "waf",
    "support", "trustedadvisor", "health", "notifications", "chatbot", "tag", "signin",
    "resource-explorer-2", "servicequotas", "s3", "cloudshell", "q",
  ]
}
