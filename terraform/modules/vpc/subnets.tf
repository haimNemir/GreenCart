resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs) # The value of count in this resource is a trigger for Terraform to create a "loop" for this block with iterations equal to the length of the public_subnet_cidrs list. This allows us to create multiple subnets based on the number of CIDR blocks provided.
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index] # The ".index" value in each iteration of the loop grows by one unit until it reaches the length of the list.
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true # This setting ensures that instances launched in this subnet will automatically receive a public IP address, which is necessary for them to be accessible from the internet.

  tags = {
    Name    = "${var.name}-public-${count.index + 1}"
    Project = var.name
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index] # Private subnets are placed in the same AZs as the public subnets, starting from AZ-a. This minimises intra-AZ data transfer costs for NAT Gateway traffic.

  tags = {
    Name    = "${var.name}-private-${count.index + 1}"
    Project = var.name
  }
}
