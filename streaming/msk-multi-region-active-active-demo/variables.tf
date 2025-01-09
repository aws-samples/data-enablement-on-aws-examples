variable "msk_cluster_name_region_a" {
  type = string
  description = "The name for the MSK Serverless cluster in region A"
  default = "cluster-a"
}

variable "msk_cluster_name_region_b" {
  type = string
  description = "The name for the MSK Serverless cluster in region B"
  default = "cluster-b"
}

variable "aws_region_a" {
  type = string
  description = "One of the target deployment regions, referred to as region A"
}

variable "aws_region_b" {
  type = string
  description = "One of the target deployment regions, referred to as region B"
}

variable "vpc_cidr_region_a" {
  type = string
  description = "A CIDR address range to use for the VPC in region A, must not conflict with existing VPC ranges"
  default = "10.0.0.0/16"
}

variable "vpc_cidr_region_b" {
  type = string
  description = "A CIDR address range to use for the VPC in region B, must not conflict with existing VPC ranges"
  default = "10.0.0.0/16"
}

variable "ec2_key_name_region_a" {
  type = string
  description = "The name of the key pair in region A to associate with the conduktor client EC2 instance"
}

variable "ec2_key_name_region_b" {
  type = string
  description = "The name of the key pair in region B to associate with the conduktor client EC2 instance"
}