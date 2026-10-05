data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = "aws-cybris-net/20-platform.tfstate"
    region = var.region
  }
}
