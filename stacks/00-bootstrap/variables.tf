variable "region" {
  description = "Region that holds the state bucket."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket that stores OpenTofu state for every stack."
  type        = string
  default     = "cybris-net-tf-bucket"
}

variable "noncurrent_version_days" {
  description = "Days a superseded state version is kept before it expires."
  type        = number
  default     = 90
}
