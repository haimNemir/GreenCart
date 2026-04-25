resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0" # Open route from inside the VPC to the internet, using the IGW of the VPC as the target for this route.
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name    = "${var.name}-public-rt"
    Project = var.name
  }
}

resource "aws_route_table_association" "public" { # Associating this route table with the public subnets. This ensures that the public subnets can access the internet through the IGW.
  count          = length(aws_subnet.public) # It looks like we have only one resource of aws_subnet.public, but in fact we have as many as the length of the public_subnet_cidrs list.
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}




resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    # Route outbound traffic from the private subnet through the NAT Gateway. This allows instances 
    # in the private subnet to reach the internet (e.g. to pull Docker images) without being 
    # directly reachable from the internet.
    cidr_block     = "0.0.0.0/0" # Tell - All traffic inside going to: "nat_gateway_id".
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name    = "${var.name}-private-rt"
    Project = var.name
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
