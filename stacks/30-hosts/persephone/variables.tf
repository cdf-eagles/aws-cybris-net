variable "region" {
  description = "Region the host lives in; must match 20-platform."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Bucket that stores OpenTofu state, from 00-bootstrap; this stack reads 20-platform's outputs from it."
  type        = string
  default     = "cybris-net-tf-bucket"
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair the instance was launched with; supplied by op.env, never committed, because the name carries an account name."
  type        = string
  sensitive   = true
}

variable "login_account_name" {
  description = "Name of the personal login account the first boot creates; supplied by op.env, never committed."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.login_account_name)) && !contains(["root", "toor", "ec2-user"], var.login_account_name)
    error_message = "The login account name must be a lowercase user name of at most 32 characters, and not root, toor, or ec2-user."
  }
}

variable "login_account_uid" {
  description = "User ID (UID) of the login account, which already owns its home directory on the home volume; supplied by op.env, never committed."
  type        = number
  sensitive   = true

  validation {
    condition     = floor(var.login_account_uid) == var.login_account_uid && var.login_account_uid >= 500 && var.login_account_uid < 1000
    error_message = "The login account UID must be a whole number from 500 to 999: below the 1000 kept for ec2-user and the 1001 upward that the image's own accounts take."
  }
}

variable "login_account_gid" {
  description = "Group ID (GID) of the login account's primary group, which already owns its home directory on the home volume; supplied by op.env, never committed."
  type        = number
  sensitive   = true

  validation {
    condition     = floor(var.login_account_gid) == var.login_account_gid && var.login_account_gid >= 500 && var.login_account_gid < 1000
    error_message = "The login account GID must be a whole number from 500 to 999: below the 1000 kept for ec2-user and the 1001 upward that the image's own accounts take."
  }
}

variable "format_blank_data_volumes" {
  description = "Lets the first boot label and format a data volume that has no partition table, file system, or GELI metadata. Off by default: set it only for a rebuild whose data volumes are new and empty. The user data runs at the first boot only, so changing this later does nothing until the next replacement."
  type        = bool
  default     = false
}
