locals {
  default_tags = {
    Project     = "cybris.net"
    Environment = "production"
    Owner       = "infrastructure"
    ManagedBy   = "opentofu"
    Repository  = "aws-cybris-net"
    Stack       = "20-platform"
  }

  vpc_cidr = "10.1.0.0/16"

  # The third octet of each subnet doubles as its IPv6 /64 index, so the two
  # address families read the same way.
  public_subnets = {
    a = { name = "Cybris.Net Public Subnet 1", zone = "a", index = 1 }
    b = { name = "Cybris.Net Public Subnet 2", zone = "b", index = 2 }
    c = { name = "Cybris.Net Public Subnet 3", zone = "c", index = 3 }
  }

  private_subnets = {
    a = { name = "Cybris.Net Private Subnet 1", zone = "a", index = 42 }
    b = { name = "Cybris.Net Private Subnet 2", zone = "b", index = 43 }
    c = { name = "Cybris.Net Private Subnet 3", zone = "c", index = 44 }
  }

  # Services the host serves to the Internet, by port. Each entry becomes one
  # rule; the keys are the rule addresses in state.
  public_ipv4_services = {
    tcp-dns   = { protocol = "tcp", port = 53, description = "DNS over TCP from anywhere" }
    udp-dns   = { protocol = "udp", port = 53, description = "DNS over UDP from anywhere" }
    tcp-http  = { protocol = "tcp", port = 80, description = "HTTP from anywhere" }
    udp-ntp   = { protocol = "udp", port = 123, description = "NTP over UDP from anywhere" }
    tcp-https = { protocol = "tcp", port = 443, description = "HTTPS from anywhere" }
    tcp-dot   = { protocol = "tcp", port = 853, description = "DNS over TLS from anywhere" }
  }

  public_ipv6_services = {
    tcp-http  = { protocol = "tcp", port = 80, description = "HTTP from anywhere" }
    udp-ntp   = { protocol = "udp", port = 123, description = "NTP over UDP from anywhere" }
    tcp-https = { protocol = "tcp", port = 443, description = "HTTPS from anywhere" }
  }

  # Volumes that outlive the instance: imported, protected, and snapshotted.
  data_volumes = {
    home = { name = "User Home Directories" }
    web  = { name = "Apache Directories" }
  }
}
