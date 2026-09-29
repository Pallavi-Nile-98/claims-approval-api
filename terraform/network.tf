# VPC with 2 public + 2 private subnets across 2 AZs, and deliberately NO NAT gateway.
#
#   public  10.0.0.0/24, 10.0.1.0/24   -> route 0.0.0.0/0 to the internet gateway (ALB, Fargate)
#   private 10.0.10.0/24, 10.0.11.0/24 -> no internet route at all (RDS only)

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Needed so the RDS endpoint hostname resolves inside the VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

# ---------- Public subnets: ALB and Fargate tasks ----------

resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index) # 10.0.0.0/24, 10.0.1.0/24

  # Public IPs are assigned explicitly by the ECS service instead, so nothing else
  # launched here gets a (billable) public IPv4 address by accident.
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------- Private subnets: RDS only ----------

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 10.0.10.0/24, 10.0.11.0/24

  tags = { Name = "${local.name}-private-${local.azs[count.index]}", Tier = "private" }
}

# No 0.0.0.0/0 route: only the implicit "local" route inside the VPC. The database can't
# reach the internet and the internet can't reach it, whatever a security group says.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
