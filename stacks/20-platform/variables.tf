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
  description = "IPv4 ranges allowed to reach port 22: the home Internet service provider's blocks. Narrowed to the Tailscale network once every host is in the tailnet."
  type        = list(string)
  default = [
    "47.182.0.0/15",
    "47.184.0.0/14",
    "47.188.0.0/15",
    "47.190.0.0/16",
  ]
}

variable "snapshot_retention_count" {
  description = "Daily snapshots Data Lifecycle Manager keeps per volume."
  type        = number
  default     = 7
}
