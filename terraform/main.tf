terraform {
  required_version = ">= 1.5"
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}

provider "aws" {
  region = var.region
}

locals {
  create_iam       = var.existing_instance_profile == ""
  instance_profile = local.create_iam ? aws_iam_instance_profile.cw[0].name : var.existing_instance_profile
}

data "aws_vpc" "default" {
  default = true
}

# Ubuntu 22.04 LTS (Canonical's official AMIs)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- SSH key pair (private key saved next to these files) ----------
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project}-tf-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "pem" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/${var.project}-tf-key.pem"
  file_permission = "0400"
}

# ---------- Security group ----------
resource "aws_security_group" "this" {
  name        = "${var.project}-tf-sg"
  description = "TaskSphere: SSH, HTTP, Jenkins, Kubernetes NodePorts"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP (Nginx Ingress)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Kubernetes NodePort range (Grafana 30300, Prometheus 30090)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-tf-sg" }
}

# ---------- IAM role so the CloudWatch agent can publish metrics/logs ----------
resource "aws_iam_role" "cw" {
  count = local.create_iam ? 1 : 0
  name  = "${var.project}-tf-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cw" {
  count      = local.create_iam ? 1 : 0
  role       = aws_iam_role.cw[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "cw" {
  count = local.create_iam ? 1 : 0
  name  = "${var.project}-tf-cw-profile"
  role  = aws_iam_role.cw[0].name
}

# ---------- EC2 instance ----------
resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = local.instance_profile

  root_block_device {
    volume_size = var.disk_size_gb
    volume_type = "gp3"
  }

  tags = { Name = "${var.project}-server" }
}

# Fixed public IP so the address survives stop/start
resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"
  tags     = { Name = "${var.project}-eip" }
}

# ---------- Ansible inventory, generated for Step 3 ----------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
    [tasksphere]
    ${aws_eip.this.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${abspath(local_sensitive_file.pem.filename)} ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
}
