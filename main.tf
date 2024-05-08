#Provider
provider "aws" {
  region = "us-east-1"  # Set your desired region
}

#vpc creation
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"  # Set your desired CIDR block for the VPC

  tags = {
    Name = "my_vpc"
  }
}

#subnet creations

resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"  # Set your desired CIDR block for the subnet
  availability_zone = "us-east-1a"  # Set your desired availability zone
  map_public_ip_on_launch = true

  tags = {
    Name = "my_subnet"
  }
}

resource "aws_subnet" "my_subnet2" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.2.0/24"  # Set your desired CIDR block for the subnet
  availability_zone = "us-east-1b"  # Set your desired availability zone
  map_public_ip_on_launch = true

  tags = {
    Name = "my_subnet2"
  }
}

resource "aws_subnet" "my_subnet3" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.3.0/24"  # Set your desired CIDR block for the subnet
  availability_zone = "us-east-1c"  # Set your desired availability zone
  map_public_ip_on_launch = true

  tags = {
    Name = "my_subnet3"
  }
}


#IGW creation

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

#creating routing table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"  # Destination CIDR block for the route
    gateway_id = aws_internet_gateway.my_igw.id  # ID of the internet gateway or other gateway
  }
}

#routing table association
resource "aws_route_table_association" "my_subnet_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
  #map_public_ip_on_launch = true
}

resource "aws_route_table_association" "my_subnet_association2" {
  subnet_id      = aws_subnet.my_subnet2.id
  route_table_id = aws_route_table.my_route_table.id
  #map_public_ip_on_launch = true
}

resource "aws_route_table_association" "my_subnet_association3" {
  subnet_id      = aws_subnet.my_subnet3.id
  route_table_id = aws_route_table.my_route_table.id
  #map_public_ip_on_launch = true
}

#security group creation

resource "aws_security_group" "my_security_group" {
  name        = "my-security-group"
  description = "My security group description"
  vpc_id      = aws_vpc.my_vpc.id  # Replace with your VPC ID

  // Inbound rule allowing SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Inbound rule allowing HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Inbound rule allowing all traffic from anywhere
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Outbound rule allowing all traffic to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


#iam role creation for eks cluster

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "example" {
  name               = "eks-cluster-example"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.example.name
}

#eks cluster creation
resource "aws_eks_cluster" "example" {
  name     = "EKS_CLOUD"
  role_arn = aws_iam_role.example.arn

  vpc_config {
    subnet_ids = [aws_subnet.my_subnet.id, aws_subnet.my_subnet2.id]
    security_group_ids = [aws_security_group.my_security_group.id]
    endpoint_public_access  = false
    endpoint_private_access = true
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSClusterPolicy,
  ]
}


#create iam role for workernode group
resource "aws_iam_role" "example-node" {
  name = "eks-node-group-cloud"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.example-node.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.example-node.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.example-node.name
}



#create worker node group
resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "example-node"
  node_role_arn   = aws_iam_role.example-node.arn
  subnet_ids = [aws_subnet.my_subnet.id, aws_subnet.my_subnet2.id]
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  instance_types = ["t2.micro"] // Specify your instance type
  capacity_type  = "SPOT"        // Specify capacity type as "SPOT"

  # update_config {
  #   max_unavailable = 1
  # }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  ]
}