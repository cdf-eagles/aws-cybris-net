terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "cybris-net-tf-bucket"
    key          = "aws-cybris-net/10-account.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
