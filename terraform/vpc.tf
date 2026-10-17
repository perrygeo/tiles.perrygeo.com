resource "aws_vpc" "tiles" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "tiles" }
}

resource "aws_subnet" "tiles" {
  vpc_id                  = aws_vpc.tiles.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = { Name = "tiles" }
}

resource "aws_internet_gateway" "tiles" {
  vpc_id = aws_vpc.tiles.id

  tags = { Name = "tiles" }
}

resource "aws_route_table" "tiles" {
  vpc_id = aws_vpc.tiles.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tiles.id
  }

  tags = { Name = "tiles" }
}

resource "aws_route_table_association" "tiles" {
  subnet_id      = aws_subnet.tiles.id
  route_table_id = aws_route_table.tiles.id
}
