terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.82.2"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region_a
  alias = "aws_region_a"
}

provider "aws" {
  region = var.aws_region_b
  alias = "aws_region_b"
}

module "baseline_environment_network_a" {
  source = "./modules/baseline-network"
  providers = {
    aws = aws.aws_region_a
  }
  vpc_cidr = var.vpc_cidr_region_a
  ec2_key_name = var.ec2_key_name_region_a
}

module "baseline_environment_network_b" {
  source = "./modules/baseline-network"
  providers = {
    aws = aws.aws_region_b
  }
  vpc_cidr = var.vpc_cidr_region_b
  ec2_key_name = var.ec2_key_name_region_b
}


// MSK serverless cluster in region A
resource "aws_msk_serverless_cluster" "msk_cluster_a" {
  provider = aws.aws_region_a
  cluster_name = var.msk_cluster_name_region_a

  vpc_config {
    subnet_ids         = module.baseline_environment_network_a.vpc_private_subnet_ids
    security_group_ids = [module.baseline_environment_network_a.intra_security_group_id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }
}

// MSK serverless cluster in region B
resource "aws_msk_serverless_cluster" "msk_cluster_b" {
  provider = aws.aws_region_b
  cluster_name = var.msk_cluster_name_region_b

  vpc_config {
    subnet_ids         = module.baseline_environment_network_b.vpc_private_subnet_ids
    security_group_ids = [module.baseline_environment_network_b.intra_security_group_id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }
}

// Security groups are not supported for cross-region replicators. Instead, use a resource-based permissions 
// policy attached to the source cluster to allow the replicator to connect to it.
resource "aws_msk_cluster_policy" "msk_cluster_a_policy" {
  provider = aws.aws_region_a
  cluster_arn = aws_msk_serverless_cluster.msk_cluster_a.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "MskClusterPolicy"
      Effect = "Allow"
      Principal = {
        "Service": "kafka.amazonaws.com"
      }
      Action = [
        "kafka:Describe*",
        "kafka:Get*",
        "kafka:CreateVpcConnection",
        "kafka:GetBootstrapBrokers",
      ]
      Resource = aws_msk_serverless_cluster.msk_cluster_a.arn
    }]
  })
}

resource "aws_msk_cluster_policy" "msk_cluster_b_policy" {
  provider = aws.aws_region_b
  cluster_arn = aws_msk_serverless_cluster.msk_cluster_b.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "MskClusterPolicy"
      Effect = "Allow"
      Principal = {
        "Service": "kafka.amazonaws.com"
      }
      Action = [
        "kafka:Describe*",
        "kafka:Get*",
        "kafka:CreateVpcConnection",
        "kafka:GetBootstrapBrokers",
      ]
      Resource = aws_msk_serverless_cluster.msk_cluster_b.arn
    }]
  })
}

// deploy required roles for use by the EC2 conduktor client 
// and MSK replicator 
module "baseline_roles" {
  source = "./modules/baseline-roles"
}


// ec2 instance for conduktor client 
data "aws_ami" "linux_ami_a" {
  provider = aws.aws_region_a
  most_recent = true
  owners      = ["amazon"]
  filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }

    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}

data "aws_ami" "linux_ami_b" {
  provider = aws.aws_region_b
  most_recent = true
  owners      = ["amazon"]
  filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    }

    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}

// region a instance 
resource "aws_instance" "conduktor_client_a" {
  provider = aws.aws_region_a
  ami = data.aws_ami.linux_ami_a.id
  key_name = var.ec2_key_name_region_a
  associate_public_ip_address = false
  instance_type = "t3.medium"
  subnet_id     = module.baseline_environment_network_a.vpc_private_subnet_ids[0]
  vpc_security_group_ids = [module.baseline_environment_network_a.intra_security_group_id]
  iam_instance_profile = module.baseline_roles.ssm_profile_name
  user_data_replace_on_change = true
  user_data = <<-EOF
${file("user_data.sh")}
EOF

  root_block_device {
    encrypted = true
  }

  monitoring = true

  tags = {
    Name = "conduktor-client-a"
  }
}

// region b instance 
resource "aws_instance" "conduktor_client_b" {
  provider = aws.aws_region_b
  ami = data.aws_ami.linux_ami_b.id
  key_name = var.ec2_key_name_region_b
  associate_public_ip_address = false
  instance_type = "t3.medium"
  subnet_id     = module.baseline_environment_network_b.vpc_private_subnet_ids[0]
  vpc_security_group_ids = [module.baseline_environment_network_b.intra_security_group_id]
  iam_instance_profile = module.baseline_roles.ssm_profile_name
  user_data_replace_on_change = true
  user_data = <<-EOF
${file("user_data.sh")}
EOF

  root_block_device {
    encrypted = true
  }

  monitoring = true

  tags = {
    Name = "conduktor-client-b"
  }
}

// MSK replicator for Cluster-A to Cluster-B replication
resource "aws_msk_replicator" "a-to-b-replicator" {
  provider = aws.aws_region_b // replicator must be in target region 
  replicator_name            = "a-to-b-replicator"
  description                = "Replicate from Cluster A to Cluster B"
  service_execution_role_arn = module.baseline_roles.msk_replicator_role_arn

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_serverless_cluster.msk_cluster_a.arn
    }

    vpc_config {
      subnet_ids          = module.baseline_environment_network_a.vpc_private_subnet_ids
      security_groups_ids = [module.baseline_environment_network_a.intra_security_group_id]
    }
  }

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_serverless_cluster.msk_cluster_b.arn
    }

    vpc_config {
      subnet_ids          = module.baseline_environment_network_b.vpc_private_subnet_ids
      security_groups_ids = [module.baseline_environment_network_b.intra_security_group_id]
    }
  }

  replication_info_list {
    source_kafka_cluster_arn = aws_msk_serverless_cluster.msk_cluster_a.arn
    target_kafka_cluster_arn = aws_msk_serverless_cluster.msk_cluster_b.arn
    target_compression_type  = "NONE"

    topic_replication {
      topics_to_replicate = [".*"]
      topic_name_configuration {
        type = "IDENTICAL" // topics will have same name in target as in source 
      }
      starting_position {
        type = "LATEST"
      }
      copy_access_control_lists_for_topics = false // ACLs not supported by serverless
    }

    consumer_group_replication {
      consumer_groups_to_replicate = [".*"]
    }
  }
}


resource "aws_msk_replicator" "b-to-a-replicator" {
  provider = aws.aws_region_a
  replicator_name            = "b-to-a-replicator"
  description                = "Replicate from Cluster B to Cluster A"
  service_execution_role_arn = module.baseline_roles.msk_replicator_role_arn

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_serverless_cluster.msk_cluster_a.arn
    }

    vpc_config {
      subnet_ids          = module.baseline_environment_network_a.vpc_private_subnet_ids
      security_groups_ids = [module.baseline_environment_network_a.intra_security_group_id]
    }
  }

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = aws_msk_serverless_cluster.msk_cluster_b.arn
    }

    vpc_config {
      subnet_ids          = module.baseline_environment_network_b.vpc_private_subnet_ids
      security_groups_ids = [module.baseline_environment_network_b.intra_security_group_id]
    }
  }

  replication_info_list {
    source_kafka_cluster_arn = aws_msk_serverless_cluster.msk_cluster_b.arn
    target_kafka_cluster_arn = aws_msk_serverless_cluster.msk_cluster_a.arn
    target_compression_type  = "NONE"


    topic_replication {
      topics_to_replicate = [".*"]
      topic_name_configuration {
        type = "IDENTICAL" // topics will have same name in target as in source 
      }
      starting_position {
        type = "LATEST"
      }
      copy_access_control_lists_for_topics = false // ACLs not supported by serverless
    }

    consumer_group_replication {
      consumer_groups_to_replicate = [".*"]
    }
  }
}



output "conduktor_client_instance_id_a" {
  value = aws_instance.conduktor_client_a.id
  description = "Instance id of the conduktor client in region A"
}

output "conduktor_client_instance_id_b" {
  value = aws_instance.conduktor_client_b.id
  description = "Instance id of the conduktor client in region B"
}