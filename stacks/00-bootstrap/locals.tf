locals {
  default_tags = {
    Project     = "cybris.net"
    Environment = "production"
    Owner       = "infrastructure"
    ManagedBy   = "opentofu"
    Repository  = "aws-cybris-net"
    Stack       = "00-bootstrap"
  }
}
