resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:flow logs cost more than one host's traffic is worth; GuardDuty reads the same flows for free
  cidr_block                       = local.vpc_cidr
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name      = "Cybris.Net VPC"
    Protected = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = cidrsubnet(local.vpc_cidr, 8, each.value.index)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, each.value.index)
  availability_zone               = "${var.region}${each.value.zone}"
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = true

  tags = {
    Name = each.value.name
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = cidrsubnet(local.vpc_cidr, 8, each.value.index)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, each.value.index)
  availability_zone               = "${var.region}${each.value.zone}"
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = {
    Name = each.value.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "Cybris.Net Internet Gateway"
  }
}

# The private subnets hold nothing today; an egress-only gateway costs nothing
# and gives anything placed there outbound IPv6 without a NAT gateway.
resource "aws_egress_only_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "Cybris.Net Egress-Only Internet Gateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "Cybris.Net Public Routing Table"
  }
}

resource "aws_route" "public_ipv4_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route" "public_ipv6_default" {
  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# The VPC's main route table; the private subnets use it by not being
# associated with any other.
resource "aws_default_route_table" "private" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  tags = {
    Name = "Cybris.Net Private Routing Table"
  }
}

resource "aws_route" "private_ipv6_default" {
  route_table_id              = aws_default_route_table.private.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this.id
}
