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
