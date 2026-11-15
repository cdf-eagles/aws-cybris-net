variable "region" {
  description = "Home region: where the single-region resources of this stack live."
  type        = string
  default     = "us-east-1"
}

variable "allowed_regions" {
  description = "Regions the permission sets may act in; every other region is denied. GuardDuty watches each of them."
  type        = list(string)
  default     = ["us-east-1", "us-east-2", "us-west-2"]
}

variable "state_bucket_name" {
  description = "Bucket that stores OpenTofu state, from 00-bootstrap."
  type        = string
  default     = "cybris-net-tf-bucket"
}

variable "admin_user_name" {
  description = "The administrator's Identity Center user name, exactly as typed on the start page (not an email, not a role ARN); supplied by op.env, never committed."
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Address that receives budget, GuardDuty, and alternate-contact mail; supplied by op.env."
  type        = string
  sensitive   = true
}

variable "contact_name" {
  description = "Name for the security, billing, and operations alternate contacts; supplied by op.env."
  type        = string
  sensitive   = true
}

variable "contact_title" {
  description = "Title for the alternate contacts; supplied by op.env."
  type        = string
  sensitive   = true
}

variable "contact_phone" {
  description = "Phone number for the alternate contacts, international format; supplied by op.env."
  type        = string
  sensitive   = true
}

variable "budget_limit_usd" {
  description = "Monthly cost budget in USD."
  type        = number
  default     = 70
}

variable "log_retention_days" {
  description = "Days CloudTrail and Config objects are kept before they expire."
  type        = number
  default     = 400
}

variable "github_owner" {
  description = "GitHub organisation whose repositories may assume the OIDC roles."
  type        = string
  default     = "cdf-eagles"
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner; GitHub embeds it in the OpenID Connect subject of repositories created after 2026-07-15 (`repo:<owner>@<id>/<repository>@<id>:...`)."
  type        = number
  default     = 59536280
}

variable "github_repository_ids" {
  description = "Numeric IDs of the repositories that assume the OIDC roles, by name; part of the subject for repositories on the immutable format."
  type        = map(number)
  default = {
    "aws-cybris-net"        = 1404901186
    "freebsd-cloud-img"     = 1129794967
    "mcp-allowlist-proxy"   = 1426588999
    "py-findbig"            = 1067219043
    "zpool-status-exporter" = 1228990568
  }
}

variable "sonarcloud_token" {
  description = "SonarCloud user token that the CI analyses read from Systems Manager Parameter Store. op.env reads it from 1Password; it is written through a write-only attribute, so neither the plan nor the state holds it."
  type        = string
  sensitive   = true
  ephemeral   = true
}
