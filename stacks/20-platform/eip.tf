# The public address of the DNS, NTP, and web services. It lives here, not
# with the instance, so a rebuilt host takes it over without a DNS change.
resource "aws_eip" "persephone" {
  #checkov:skip=CKV2_AWS_19:associated by the instance stack in 30-hosts, which Checkov cannot see from here
  domain = "vpc"

  tags = {
    Name      = "persephone.cybris.net Elastic IP"
    Protected = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The reverse (PTR) record AWS publishes for the address.
resource "aws_eip_domain_name" "persephone" {
  allocation_id = aws_eip.persephone.id
  domain_name   = "persephone.cybris.net."
}
