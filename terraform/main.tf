provider "aws" {
  region = "us-west-2"
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Subnet Configuration
resource "aws_subnet" "az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
}

resource "aws_subnet" "az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
}

resource "aws_subnet" "az3" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2c"
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "cluster1" {
  name               = "eks-cluster-example2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster1.name
}

# IAM Role for Worker Nodes
resource "aws_iam_role" "worker_nodes" {
  name               = "eks-worker-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole"
        ]
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker_nodes.name
}

resource "aws_iam_role_policy_attachment" "worker_nodes_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker_nodes.name
}

# EKS Cluster Configuration
resource "aws_eks_cluster" "example" {
  name     = "example-2"
  role_arn = aws_iam_role.cluster1.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = [
      aws_subnet.az1.id,
      aws_subnet.az2.id,
      aws_subnet.az3.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

# Security Group for Worker Nodes
resource "aws_security_group" "worker_nodes" {
  name        = "eks-worker-nodes-sg"
  description = "Allow all traffic within the VPC for EKS worker nodes"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch Template for Worker Nodes
resource "aws_launch_template" "worker_nodes" {
  name          = "eks-worker-node-launch-template"
  image_id      = "ami-0b4a21432a0c9c1ab" # Replace with your AMI ID
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_nodes.name
  }

  vpc_security_group_ids = [aws_security_group.worker_nodes.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "eks-worker-node"
    }
  }
}

# Auto Scaling Group for Worker Nodes
resource "aws_autoscaling_group" "worker_nodes" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.az1.id, aws_subnet.az2.id, aws_subnet.az3.id]

  launch_template {
    id      = aws_launch_template.worker_nodes.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "eks-worker-node"
    propagate_at_launch = true
  }

  health_check_type          = "EC2"
  health_check_grace_period = 300
  force_delete               = true

  depends_on = [
    aws_eks_cluster.example
  ]
}

# Instance Profile for Worker Nodes
resource "aws_iam_instance_profile" "worker_nodes" {
  name = "eks-worker-node-profile"
  role = aws_iam_role.worker_nodes.name
}

# Outputs
output "cluster_endpoint" {
  value = aws_eks_cluster.example.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.example.certificate_authority[0].data
}
