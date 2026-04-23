resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # This allows our VPC to get a DNS resolver. Even though this is a default value in AWS, we define it explicitly because it is critical: there is a DNS resolver inside each VPC you create, managed by AWS, that resolves IPs to DNS names and vice versa both inside the VPC and to the outside. Without it, containers cannot resolve each other by name.
  enable_dns_hostnames = true # This allows our VPC to assign DNS hostnames to EC2 instances with public IPs. It is required for the application instances to be reachable by hostname.

  tags = {
    Name    = "${var.name}-vpc"
    Project = var.name
  }
}
