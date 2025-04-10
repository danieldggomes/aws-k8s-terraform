provider "aws" {
  region = var.aws_region
}

# Criar uma nova VPC
resource "aws_vpc" "k8s_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = { Name = "k8s-vpc" }
}

# Criar uma subnet pública
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "k8s-public-subnet" }
}

# Criar uma subnet privada
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "k8s-private-subnet" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id
  tags   = { Name = "k8s-igw" }
}

# Elastic IP para NAT Gateway
resource "aws_eip" "nat_eip" {
  tags = { Name = "k8s-nat-eip" }
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = { Name = "k8s-nat-gateway" }
}

# Route Table pública
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "k8s-public-rt" }
}

# Route Table privada
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = { Name = "k8s-private-rt" }
}

# Route Table associations
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Security Group Kubernetes
resource "aws_security_group" "k8s_cluster_sg" {
  name        = "k8s-cluster-sg"
  description = "Allow SSH access and Kubernetes traffic"
  vpc_id      = aws_vpc.k8s_vpc.id

  ingress {
    description = "SSH"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API"
    protocol    = "tcp"
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubelet API"
    protocol    = "tcp"
    from_port   = 10250
    to_port     = 10250
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort Services"
    protocol    = "tcp"
    from_port   = 30000
    to_port     = 32767
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All internal"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-cluster-sg" }
}

# Instâncias EC2 (Exemplo)
resource "aws_instance" "control_plane" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_cluster_sg.id]
  key_name               = var.key_pair_name

  tags = { Name = "k8s-control-plane" }
}

resource "aws_instance" "workers" {
  count                  = 2
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_cluster_sg.id]
  key_name               = var.key_pair_name

  tags = { Name = "k8s-worker-${count.index + 1}" }
}
