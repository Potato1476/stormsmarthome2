terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Credentials: use AWS CLI profile or IAM role — never hardcode keys here.
  # Run: aws configure --profile fog-smarthome
  # Then: export AWS_PROFILE=fog-smarthome
}

# ── VPC & Networking ──────────────────────────────────────────────────────────

resource "aws_vpc" "fog_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "fog-smarthome-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.fog_vpc.id
  tags   = { Name = "fog-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.fog_vpc.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "fog-public-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.fog_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "fog-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# ── Security Groups ───────────────────────────────────────────────────────────
# Principle: open only what is strictly needed.

resource "aws_security_group" "cloud_sg" {
  name        = "fog-cloud-sg"
  description = "Cloud tier: MQTT + Storm UI + Storm exporter open to your IP (gateway Pi chay local)"
  vpc_id      = aws_vpc.fog_vpc.id

  # SSH — chỉ IP của bạn
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # MQTT — từ máy local (gateway Pi giả lập) + publisher dữ liệu thô.
  # Gateway nay chạy ở local nên kết nối ra Cloud qua internet → mở cho IP của bạn.
  # (Production nên dùng TLS 8883 + client cert; ở đây dùng plain 1883 cho demo.)
  ingress {
    description = "MQTT plain from your local machine (Pi sim + publisher)"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Storm UI — chỉ IP của bạn
  ingress {
    description = "Storm UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Storm exporter — để Prometheus phía local scrape metrics tầng Cloud
  ingress {
    description = "Storm exporter for local Prometheus"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Web Dashboard (iot-data-api) — truy cập từ IP của bạn
  ingress {
    description = "Web dashboard & Slack config UI"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fog-cloud-sg" }
}

# ── EC2: Cloud Tier ───────────────────────────────────────────────────────────

resource "aws_instance" "cloud" {
  ami                    = var.cloud_ami
  instance_type          = var.cloud_instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.cloud_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -e
    yum update -y
    yum install -y docker git
    systemctl enable --now docker
    usermod -aG docker ec2-user
    # Install Docker Compose v2
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  USERDATA

  tags = { Name = "fog-cloud-node", Role = "cloud" }
}

# ── Elastic IP ───────────────────────────────────────────────────────────────
# IP TĨNH: gắn EIP vào EC2 Cloud để public IP KHÔNG đổi khi stop/start.
# Nhờ vậy chỉ cần điền CLOUD_PUBLIC_IP một lần duy nhất, không phải sửa lại
# .env.gateway + prometheus mỗi lần bật lại máy.
# (Lưu ý chi phí: khi EC2 đang TẮT, AWS tính phí EIP ~0.005 USD/giờ. Khi chạy thì free.)
resource "aws_eip" "cloud" {
  domain   = "vpc"
  instance = aws_instance.cloud.id
  tags     = { Name = "fog-cloud-eip" }
}


# Gateway EC2 (FOG v1) đã GỠ khỏi config (2026-06-29) — gateway chạy LOCAL bằng docker.
# Lịch sử ở main.tf.bak. Khôi phục nếu sau này cần gateway trên EC2 thật.
