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

  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      # copia o comando da instância Rancher
      "scp -o StrictHostKeyChecking=no -i /home/ubuntu/.ssh/seu-arquivo.pem ubuntu@${aws_instance.rancher_k3s.public_ip}:/home/ubuntu/import_cmd.sh .",
      "chmod +x import_cmd.sh",
      "sudo su -c \"$(cat import_cmd.sh)\""
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/${var.key_pair_name}.pem")
      host        = self.public_ip
    }
  }

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


# EC2 Instance para Rancher com K3s
resource "aws_instance" "rancher_k3s" {
  ami                    = var.ami_id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_cluster_sg.id]
  key_name               = var.key_pair_name

  user_data = <<-EOF
              #!/bin/bash
              apt update
              apt install -y jq curl
              curl -sfL https://get.k3s.io | sh -
              sleep 30
              export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
              helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
              kubectl create namespace cattle-system
              helm install rancher rancher-stable/rancher \
                --namespace cattle-system \
                --set hostname=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4).sslip.io \
                --set replicas=1 \
                --set bootstrapPassword=dataprev00! \
                --set ingress.tls.source=rancher \
              EOF

  provisioner "remote-exec" {
    inline = [
      "sleep 180", # Aguarda o Rancher iniciar completamente
      "sudo chmod 644 /etc/rancher/k3s/k3s.yaml",
      "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml",
      "kubectl -n cattle-system rollout status deploy/rancher",
      "RANCHER_URL=https://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4).sslip.io",

      "LOGINRESPONSE=$(curl -skX POST $RANCHER_URL/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{\"username\":\"admin\",\"password\":\"dataprev00!\"}')",
      "LOGINTOKEN=$(echo $LOGINRESPONSE | jq -r .token)",

      "CLUSTERID=$(curl -skX POST $RANCHER_URL/v3/cluster -H \"Authorization: Bearer $LOGINTOKEN\" -H 'Content-Type: application/json' -d '{\"type\":\"cluster\",\"name\":\"imported-cluster\"}' | jq -r .id)",

      "curl -skX POST $RANCHER_URL/v3/clusterregistrationtoken -H \"Authorization: Bearer $LOGINTOKEN\" -H 'Content-Type: application/json' -d \"{\\\"type\\\":\\\"clusterRegistrationToken\\\",\\\"clusterId\\\":\\\"$CLUSTERID\\\"}\" > token.json",

      "IMPORT_CMD=$(cat token.json | jq -r '.manifestUrl' | xargs curl -sk | grep 'kubectl apply' | sed 's/^.*kubectl/kubectl/' | sed 's/.$//')",
      "echo $IMPORT_CMD > /home/ubuntu/import_command.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/${var.key_pair_name}.pem")
      host        = self.public_ip
    }
  }
  tags = {
    Name = "rancher-k3s-server"
  }
}
