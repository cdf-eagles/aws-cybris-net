data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "terraform_remote_state" "account" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "aws-cybris-net/10-account.tfstate"
    region = var.region
  }
}
