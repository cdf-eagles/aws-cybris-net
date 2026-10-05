locals {
  default_tags = {
    Project     = "cybris.net"
    Environment = "production"
    Owner       = "infrastructure"
    ManagedBy   = "opentofu"
    Repository  = "aws-cybris-net"
    Stack       = "30-hosts-persephone"
  }

  host_name = "persephone.cybris.net"
  platform  = data.terraform_remote_state.platform.outputs

  # Device names as the instance sees them; the attachments are adopted with
  # these and the host's fstab depends on them.
  data_volume_devices = {
    home = "/dev/xvdbb"
    web  = "/dev/xvdbc"
  }
}
