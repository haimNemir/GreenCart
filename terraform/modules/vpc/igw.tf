resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.name}-igw"
    Project = var.name
  }
}

resource "aws_eip" "nat" {
  domain = "vpc" # EIP must be in the VPC domain to be attached to a NAT Gateway.

  tags = {
    Name    = "${var.name}-nat-eip"
    Project = var.name
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # NAT Gateway must be placed in a public subnet. We use the first public subnet (AZ-a).

  tags = {
    Name    = "${var.name}-nat"
    Project = var.name
  }

  depends_on = [aws_internet_gateway.this] # The IGW must exist before the NAT Gateway can route outbound traffic.
}
