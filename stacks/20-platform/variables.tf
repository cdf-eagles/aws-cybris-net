variable "region" {
  description = "Region the platform lives in; the hosts' stacks read it from this stack's outputs."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Bucket that stores OpenTofu state, from 00-bootstrap; this stack reads 10-account's outputs from it."
  type        = string
  default     = "cybris-net-tf-bucket"
}

variable "ssh_source_cidrs" {
  description = "IPv4 ranges allowed to reach port 22 from the internet. Empty: SSH reaches the hosts over the Tailscale network only. Set only while a new instance has not yet joined the tailnet."
  type        = list(string)
  default     = []
}

variable "snapshot_retention_count" {
  description = "Daily snapshots Data Lifecycle Manager keeps per volume."
  type        = number
  default     = 7
}
