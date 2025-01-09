terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "msk-demo-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(cidrsubnets(var.vpc_cidr, 6, 6, 6, 6, 6, 6),0,3)
  public_subnets  = slice(cidrsubnets(var.vpc_cidr, 6, 6, 6, 6, 6, 6),3,6)

  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = true

}

// intra security group
// allow access from self-reference tagged resources
// and the VPC CIDR 
resource "aws_security_group" "intra_security_group" {
  
  name        = "intra-security-group"
  description = "Security group to allow self-reference and intra VPC connections"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "intra-sg"
  }
}

// ingress rule to allow self referencing 
// security group to talk to each other
resource "aws_vpc_security_group_ingress_rule" "self_reference_ingress" {
  security_group_id = aws_security_group.intra_security_group.id
  ip_protocol    = "-1"
  referenced_security_group_id = aws_security_group.intra_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_vpc_cidr" {
  security_group_id = aws_security_group.intra_security_group.id

  ip_protocol = "-1"
  cidr_ipv4   = module.vpc.vpc_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "allow_all_egress" {
  security_group_id = aws_security_group.intra_security_group.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

// s3 vpc endpoint 
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = module.vpc.private_route_table_ids
  tags = {
    Name = "s3-vpc-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type = "Interface"
  security_group_ids = [
    aws_security_group.intra_security_group.id
  ]
  private_dns_enabled = true
  subnet_ids = module.vpc.private_subnets
  ip_address_type = "ipv4"
  tags = {
    Name = "ec2-vpc-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type = "Interface"
  security_group_ids = [
    aws_security_group.intra_security_group.id
  ]
  private_dns_enabled = true
  subnet_ids = module.vpc.private_subnets
  ip_address_type = "ipv4"
  tags = {
    Name = "ssm-vpc-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type = "Interface"
  security_group_ids = [
    aws_security_group.intra_security_group.id
  ]
  private_dns_enabled = true
  subnet_ids = module.vpc.private_subnets
  ip_address_type = "ipv4"
  tags = {
    Name = "ssmmessages-vpc-endpoint"
  }
}

output "vpc_private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "intra_security_group_id" {
  value = aws_security_group.intra_security_group.id
}