# The host as it runs today. The image, the user data, and the instance type
# are adopted as found and ignored until the rebuild window, which is the one
# change that is allowed to replace this instance.
resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_126:detailed monitoring costs more than one host's graphs are worth
  #checkov:skip=CKV_AWS_135:t3 instances are EBS-optimized by default; the launch flag is what the account holds
  #checkov:skip=CKV2_AWS_41:the host calls no AWS API, so it carries no instance profile
  ami                                  = "ami-0abcc07f0bf9b612b"
  instance_type                        = "t3.medium"
  subnet_id                            = local.platform.public_subnet_ids["a"]
  vpc_security_group_ids               = [local.platform.instance_security_group_id]
  key_name                             = var.key_pair_name
  source_dest_check                    = true
  disable_api_termination              = true
  disable_api_stop                     = false
  ebs_optimized                        = false
  monitoring                           = false
  hibernation                          = false
  instance_initiated_shutdown_behavior = "stop"

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
    Name      = local.host_name
    Protected = "true"
  }

  lifecycle {
    ignore_changes = [ami, user_data, user_data_base64, instance_type]
  }
}

# The primary interface, adopted so the host can take an IPv6 address in
# place; setting the count on the instance itself would replace it.
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

resource "aws_eip_association" "this" {
  allocation_id = local.platform.eip_allocation_id
  instance_id   = aws_instance.this.id
}
