# The one group the hosts use. Rules are separate resources so each can be
# imported, reviewed, and removed on its own.
resource "aws_security_group" "instance" {
  #checkov:skip=CKV2_AWS_5:attached by the instances in 30-hosts, which Checkov cannot see from here
  name        = "default-instance-sg"
  description = "Cybris.Net Default Instance Security Group"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "Cybris.Net Default Instance Security Group"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_ipv4" {
  for_each = toset(var.ssh_source_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "SSH from the home Internet service provider"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "public_ipv4" {
  #checkov:skip=CKV_AWS_260:the web server answers port 80 to redirect to 443 and to serve ACME challenges
  for_each = local.public_services

  security_group_id = aws_security_group.instance.id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "public_ipv6" {
  #checkov:skip=CKV_AWS_260:the web server answers port 80 to redirect to 443 and to serve ACME challenges
  for_each = local.public_services

  security_group_id = aws_security_group.instance.id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv6         = "::/0"
}

resource "aws_vpc_security_group_ingress_rule" "icmp_echo_ipv4" {
  security_group_id = aws_security_group.instance.id
  description       = "ICMP echo request from anywhere"
  ip_protocol       = "icmp"
  from_port         = 8
  to_port           = 0
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "icmp_echo_ipv6" {
  security_group_id = aws_security_group.instance.id
  description       = "ICMPv6 echo request from anywhere"
  ip_protocol       = "icmpv6"
  from_port         = 128
  to_port           = 0
  cidr_ipv6         = "::/0"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  #checkov:skip=CKV_AWS_382:the host fetches packages, zone transfers, and certificates from arbitrary addresses
  security_group_id = aws_security_group.instance.id
  description       = "Anything outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  #checkov:skip=CKV_AWS_382:the host fetches packages, zone transfers, and certificates from arbitrary addresses
  security_group_id = aws_security_group.instance.id
  description       = "Anything outbound"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# The VPC's own default group, attached to nothing. The empty rule sets are
# deliberate: omitting them would leave the group's rules alone, and the point
# is to strip the egress rule it was created with so it can never be used by
# accident.
resource "aws_default_security_group" "this" {
  vpc_id  = aws_vpc.this.id
  ingress = []
  egress  = []

  tags = {
    Name = "Cybris.Net Default VPC Security Group (unused)"
  }
}
