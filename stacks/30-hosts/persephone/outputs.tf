output "instance_id" {
  description = "The instance."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "The instance's private IPv4 address."
  value       = aws_instance.this.private_ip
}

output "ipv6_addresses" {
  description = "The IPv6 addresses on the primary interface, for the AAAA records."
  value       = aws_network_interface.primary.ipv6_addresses
}
