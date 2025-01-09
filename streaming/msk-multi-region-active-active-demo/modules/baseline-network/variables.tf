variable "vpc_cidr" {
  type = string
  description = "A CIDR address range to use for the VPC, must not conflict with existing VPC ranges"
}

variable "ec2_key_name" {
  type = string
  description = "The name of the key pair to associate with the conduktor client EC2 instance"
}