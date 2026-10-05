output "vpc_id" {
  description = "The VPC every host lives in."
  value       = aws_vpc.this.id
}

output "vpc_ipv6_cidr_block" {
  description = "The Amazon-provided IPv6 /56 of the VPC."
  value       = aws_vpc.this.ipv6_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs by availability-zone letter."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "Private subnet IDs by availability-zone letter."
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "instance_security_group_id" {
  description = "The security group the hosts attach."
  value       = aws_security_group.instance.id
}

output "kms_key_arn" {
  description = "The key that encrypts every volume."
  value       = aws_kms_key.persephone.arn
}

output "eip_allocation_id" {
  description = "Allocation ID of the public address; 30-hosts associates it."
  value       = aws_eip.persephone.id
}

output "eip_public_ip" {
  description = "The public address of the DNS, NTP, and web services."
  value       = aws_eip.persephone.public_ip
}

output "data_volume_ids" {
  description = "Data volume IDs by role; 30-hosts attaches them."
  value       = { for k, v in aws_ebs_volume.data : k => v.id }
}
