variable "region" {
  type = string
  description = "The AWS region to deploy resources into. Pre-requisites must exist in same region"
}

variable "vpc_cidr" {
  type = string
  description = "A CIDR address range to use for the VPC, must not conflict with existing VPC ranges"
}

variable "name_prefix" {
  type = string
  default = "zero-etl-demo"
  description = "Common prefix to use for naming resources deployed as part of the demo"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

// vpc to contain demo resources 
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = slice(cidrsubnets(var.vpc_cidr, 6, 6, 6, 6, 6, 6),0,3)
  public_subnets  = slice(cidrsubnets(var.vpc_cidr, 6, 6, 6, 6, 6, 6),3,6)

  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = true

}

// self referecing security group so that associated resources can speak to each other 
resource "aws_security_group" "intra_security_group" {
  name        = "${var.name_prefix}-intra-security-group"
  description = "Self referencing security group for demo"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-self-referencing-sg"
  }
}

// Redshift serverless data warehouse - namespace and workgroup
resource "aws_redshiftserverless_namespace" "demo_namespace" {
  namespace_name = "${var.name_prefix}-namespace"
  admin_username = "demo"
  manage_admin_password = true
}


resource "aws_redshiftserverless_workgroup" "demo_workgroup" {
  namespace_name      = aws_redshiftserverless_namespace.demo_namespace.namespace_name
  workgroup_name      = "${var.name_prefix}-workgroup"
  base_capacity       = 8
  publicly_accessible = false

  subnet_ids = module.vpc.private_subnets
  security_group_ids = [ aws_security_group.intra_security_group.id ]

  // required to use case sensitivity for zero ETL 
  config_parameter {
    parameter_key   = "enable_case_sensitive_identifier"
    parameter_value = "true"
  }

  config_parameter {
    parameter_key   = "auto_mv"
    parameter_value = "true"
  }

  config_parameter {
    parameter_key   = "datestyle"
    parameter_value = "ISO, MDY"
  }

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }

  config_parameter {
    parameter_key   = "query_group"
    parameter_value = "default"
  }

  config_parameter {
    parameter_key   = "search_path"
    parameter_value = "$user, public"
  }

  config_parameter {
    parameter_key = "use_fips_ssl"
    parameter_value = "false"
  }

  config_parameter {
    parameter_key = "require_ssl"
    parameter_value = "false"
  }

  config_parameter {
    parameter_key = "max_query_execution_time"
    parameter_value = "14400"
  }
}

// aurora postgres serverless with custom cluster parameter group to enable zero ETL 
resource "aws_rds_cluster_parameter_group" "custom_aurora_cluster_parameter_group" {
  name        = "${var.name_prefix}-aurora-cluster-parameter-group"
  family      = "aurora-mysql8.0"
  description = "Custom Aurora Cluster Parameter Group for zero ETL demo"

  parameter {
    name  = "aurora_enhanced_binlog"
    value = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "binlog_backup"
    value = "0"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "binlog_format"
    value = "ROW"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "binlog_replication_globaldb"
    value = "0"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "binlog_row_image"
    value = "full"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "binlog_row_metadata"
    value = "full"
    apply_method = "pending-reboot"
  }
}

// subnet group for database, using public for demo purposes to allow simpler connectivity from SQL client 
resource "aws_db_subnet_group" "public_subnet_group" {
  name       = "${var.name_prefix}-aurora-public-subnet-group"
  subnet_ids = module.vpc.public_subnets

  tags = {
    Name = "Demo db public subnet group"
  }
}

// Aurora MySQL Serverless cluster 
resource "aws_rds_cluster" "demo_mysql_cluster" {
  cluster_identifier = "${var.name_prefix}-source-db"
  engine             = "aurora-mysql"
  engine_mode        = "provisioned"
  engine_version     = "8.0.mysql_aurora.3.05.2"
  database_name      = "demo"
  master_username    = "demo"
  // password managed by Secrets Manager
  manage_master_user_password = true
  storage_encrypted  = true
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.custom_aurora_cluster_parameter_group.name
  db_subnet_group_name = aws_db_subnet_group.public_subnet_group.name
  vpc_security_group_ids = [ aws_security_group.intra_security_group.id ]
  skip_final_snapshot = true

  serverlessv2_scaling_configuration {
    max_capacity = 2.0
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "demo_mysql_instance" {
  cluster_identifier = aws_rds_cluster.demo_mysql_cluster.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.demo_mysql_cluster.engine
  engine_version     = aws_rds_cluster.demo_mysql_cluster.engine_version
  // you could consider making publicly accessible in demo to make connecting from local SQL client easier
  // it is recommended to keep false, especially for production or non-sample data
  publicly_accessible = false
}


// Redshift in private subnet, so need to create VPC connection from Quicksight to allow access
// This requires IAM execution role for QuickSight VPC connection
data "aws_iam_policy_document" "quicksight-vpc-policy-doc" {
  statement {
    actions = [
        "ec2:CreateNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "quicksight-vpc-policy" {
  name = "${var.name_prefix}-quicksight-vpc-policy"
  policy = data.aws_iam_policy_document.quicksight-vpc-policy-doc.json
}
resource "aws_iam_role" "quicksight-vpc-role" {
  name = "${var.name_prefix}-quicksight-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_policy_attachment" "quicksight-policy-attach" {
  name = "${var.name_prefix}-quicksight-policy-attach"
  roles = [
    aws_iam_role.quicksight-vpc-role.name
  ]
  policy_arn = aws_iam_policy.quicksight-vpc-policy.arn
}
