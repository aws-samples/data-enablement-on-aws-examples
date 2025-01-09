terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }

  required_version = ">= 1.2.0"
}


// conductor client EC2 role
data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "ssm_core_policy" {
    arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "kafka_policy_doc" {
  statement {
    actions = [
        "kafka:*",
        "kafka-cluster:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "kafka_policy" {
  policy = data.aws_iam_policy_document.kafka_policy_doc.json
}

resource "aws_iam_role" "ec2_conduktor_role" {
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json
}

// MSK replicator role
data "aws_iam_policy_document" "msk_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["kafka.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "msk_replicator_role" {
  assume_role_policy = data.aws_iam_policy_document.msk_assume_role_policy.json
}

resource "aws_iam_policy_attachment" "kafka_policy_attach" {
  name = "kafka-policy-attach"
  roles = [
    aws_iam_role.ec2_conduktor_role.name,
    aws_iam_role.msk_replicator_role.name
  ]
  policy_arn = aws_iam_policy.kafka_policy.arn
}


resource "aws_iam_role_policy_attachment" "ec2_role_policy_attach" {
  role       = "${aws_iam_role.ec2_conduktor_role.name}"
  policy_arn = "${data.aws_iam_policy.ssm_core_policy.arn}"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  role = aws_iam_role.ec2_conduktor_role.name
}

output "ssm_profile_name" {
  value = aws_iam_instance_profile.ssm_profile.name
}

output "msk_replicator_role_arn" {
    value = aws_iam_role.msk_replicator_role.arn
}