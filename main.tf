resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2 # Deploy in 2 AZs for high availability
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2) # Offset for private subnets
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = 2 # One NAT Gateway per public subnet
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-gateway-${count.index}"
  }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "nat" {
  count = 2
  vpc   = true
  tags = {
    Name = "${var.project_name}-nat-eip-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${count.index}"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Outputs for other modules
output "vpc_id" {
  value = aws_vpc.main.id
}
output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

module "vpc" {
  source       = "./modules/vpc"
  project_name = var.project_name
  aws_region   = var.aws_region
}

module "rds" {
  source           = "./modules/rds"
  project_name     = var.project_name
  vpc_id           = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  db_password      = var.db_password
  ecs_sg_id        = module.ecs.ecs_sg_id # Dependency on ECS security group
}

module "redis" {
  source           = "./modules/redis"
  project_name     = var.project_name
  vpc_id           = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  redis_password   = var.redis_password
  ecs_sg_id        = module.ecs.ecs_sg_id # Dependency on ECS security group
}

module "networking" {
  source                           = "./modules/networking"
  project_name                     = var.project_name
  vpc_id                           = module.vpc.vpc_id
  public_subnet_ids                = module.vpc.public_subnet_ids
  domain_name                      = var.domain_name
  root_domain                      = var.root_domain
  certificate_arn                  = "arn:aws:acm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:certificate/${var.acm_certificate_id}" # Replace with your ACM certificate ARN
  certificate_validation_options   = data.aws_acm_certificate.n8n.domain_validation_options
}

module "ecs" {
  source             = "./modules/ecs"
  project_name       = var.project_name
  aws_region         = var.aws_region
  private_subnet_ids = module.vpc.private_subnet_ids
  private_subnet_cidrs = module.vpc.private_subnet_ids_cidr_blocks # Add this output to VPC module
  alb_target_group_arn = module.networking.alb_target_group_arn
  alb_sg_id          = module.networking.alb_sg_id
  db_host            = module.rds.db_instance_address
  redis_host         = module.redis.redis_endpoint_address
  n8n_encryption_key = var.n8n_encryption_key
  n8n_basic_auth_user = var.n8n_basic_auth_user
  n8n_basic_auth_password = var.n8n_basic_auth_password
  db_password        = var.db_password
  redis_password     = var.redis_password
  domain_name        = var.domain_name
  n8n_docker_image   = var.n8n_docker_image
}

data "aws_caller_identity" "current" {}

data "aws_acm_certificate" "n8n" {
  domain   = var.domain_name
  statuses = ["ISSUED"]
}