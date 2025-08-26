############################################
# vpc.tf
############################################

# 1. VPC 생성
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# 2. 가용 영역(AZ) 데이터 소스
data "aws_availability_zones" "available" {
  state = "available"
}

# 3. 퍼블릭 서브넷 생성
resource "aws_subnet" "public" {
  for_each = {
    "a" = "10.0.1.0/24"
    "b" = "10.0.2.0/24"
    "c" = "10.0.3.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-subnet-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                     = "1"
  }
}

# 4. 인터넷 게이트웨이 생성
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# 5. 퍼블릭 라우팅 테이블 생성
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# 6. 라우팅 테이블과 서브넷 연결
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# 7. NAT 게이트웨이용 EIP 생성
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

# 8. NAT 게이트웨이 생성
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  # 첫 번째 퍼블릭 서브넷에 NAT 게이트웨이를 위치시킵니다.
  subnet_id     = values(aws_subnet.public)[0].id

  tags = {
    Name = "${var.cluster_name}-nat-gw"
  }

  # aws_eip.nat 리소스가 생성된 후에 이 리소스가 생성되도록 명시적 의존성을 추가합니다.
  depends_on = [aws_eip.nat]
}

# 9. 프라이빗 서브넷 생성
resource "aws_subnet" "private" {
  for_each = {
    "a" = "10.0.101.0/24"
    "b" = "10.0.102.0/24"
    "c" = "10.0.103.0/24"
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "${var.aws_region}${each.key}"

  tags = {
    Name = "${var.cluster_name}-private-subnet-${each.key}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"            = "1"
  }
}

# 10. 프라이빗 라우팅 테이블 생성
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

# 11. 프라이빗 라우팅 테이블과 서브넷 연결
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
