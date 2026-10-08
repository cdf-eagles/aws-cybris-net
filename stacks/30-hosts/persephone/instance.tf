# The image and the user data serve the first boot only and are ignored after
# it, so the instance is replaced only by an explicit
# `tofu apply -replace=aws_instance.this`.
resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_126:detailed monitoring costs more than one host's graphs are worth
  #checkov:skip=CKV_AWS_135:t3a instances are EBS-optimized by default, whatever the launch flag says
  #checkov:skip=CKV2_AWS_41:the host calls no AWS API, so it carries no instance profile
  ami           = "ami-00a1141286ec55116"
  instance_type = "t3a.small"
  key_name      = var.key_pair_name
  user_data = templatefile("${path.module}/user_data.sh", {
    login_account_name = var.login_account_name
    login_account_uid  = var.login_account_uid
    login_account_gid  = var.login_account_gid
  })
  disable_api_termination              = false
  disable_api_stop                     = false
  ebs_optimized                        = false
  monitoring                           = false
  hibernation                          = false
  instance_initiated_shutdown_behavior = "stop"

  primary_network_interface {
    network_interface_id = aws_network_interface.primary.id
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_protocol_ipv6          = "disabled"
    instance_metadata_tags      = "disabled"
  }

  private_dns_name_options {
    hostname_type                        = "ip-name"
    enable_resource_name_dns_a_record    = false
    enable_resource_name_dns_aaaa_record = false
  }

  maintenance_options {
    auto_recovery = "default"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    kms_key_id            = local.platform.kms_key_arn
    delete_on_termination = true

    tags = {
      Name      = "${local.host_name} Root Disk"
      Protected = "true"
      Backup    = "daily"
    }
  }

  tags = {
    Name = local.host_name
  }

  lifecycle {
    ignore_changes = [ami, user_data, user_data_base64]
  }
}

# The primary interface outlives the instance: each instance is launched on
# it, so the private address, the Internet Protocol version 6 (IPv6) address,
# and the address association survive a rebuild. Amazon Elastic Compute Cloud
# (EC2) attaches an existing interface with delete-on-termination off; the
# first instance's attachment was switched off by hand before its replacement.
resource "aws_network_interface" "primary" {
  subnet_id          = local.platform.public_subnet_ids["a"]
  security_groups    = [local.platform.instance_security_group_id]
  source_dest_check  = true
  ipv6_address_count = 1

  tags = {
    Name = "${local.host_name} primary interface"
  }
}

resource "aws_volume_attachment" "data" {
  for_each = local.data_volume_devices

  device_name = each.value
  volume_id   = local.platform.data_volume_ids[each.key]
  instance_id = aws_instance.this.id
}

# Bound to the interface rather than the instance, so a rebuild leaves it in
# place.
resource "aws_eip_association" "this" {
  allocation_id        = local.platform.eip_allocation_id
  network_interface_id = aws_network_interface.primary.id
  private_ip_address   = aws_network_interface.primary.private_ip
}
