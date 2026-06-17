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

# ── EC2: Gateway Tier (FOG v1 — code thầy + TagAwareScheduler) ────────────────
# Một Storm cluster duy nhất trải trên 2 máy nên worker 2 phía phải kết nối
# trực tiếp với nhau (netty 6700-6703 + acker). Laptop sau NAT không nhận được
# kết nối từ Cloud → gateway phải là EC2 có public IP.
# t3.small (2GB) để máy ổn định; supervisor1 bên trong bị giới hạn 1GB/1vCPU
# bằng docker (mô phỏng Pi 3) qua gateway/.env.

resource "aws_security_group" "gateway_sg" {
  name        = "fog-gateway-sg"
  description = "Gateway tier: MQTT from your IP, Storm worker ports from cloud node"
  vpc_id      = aws_vpc.fog_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # Publisher (laptop) gửi dữ liệu thô vào broker local của gateway
  ingress {
    description = "MQTT raw data from your machine"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fog-gateway-sg" }
}

resource "aws_instance" "gateway" {
  ami                    = var.cloud_ami
  instance_type          = var.gateway_instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gateway_sg.id]

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -e
    yum update -y
    yum install -y docker git
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  USERDATA

  tags = { Name = "fog-gateway-node", Role = "gateway" }
}

resource "aws_eip" "gateway" {
  domain   = "vpc"
  instance = aws_instance.gateway.id
  tags     = { Name = "fog-gateway-eip" }
}

# ── SG rules giữa 2 máy (tách riêng để tránh vòng phụ thuộc EIP ↔ SG) ─────────
# Hai máy gọi nhau qua PUBLIC IP (extra_hosts trong compose) nên rule mở theo EIP.

# Gateway → Cloud: ZooKeeper, Nimbus Thrift, worker netty, MySQL (Bolt_avg ghi DB)
resource "aws_security_group_rule" "cloud_from_gw_zk" {
  type              = "ingress"
  security_group_id = aws_security_group.cloud_sg.id
  from_port         = 2181
  to_port           = 2181
  protocol          = "tcp"
  cidr_blocks       = ["${aws_eip.gateway.public_ip}/32"]
  description       = "ZooKeeper from gateway node"
}

resource "aws_security_group_rule" "cloud_from_gw_nimbus" {
  type              = "ingress"
  security_group_id = aws_security_group.cloud_sg.id
  from_port         = 6627
  to_port           = 6627
  protocol          = "tcp"
  cidr_blocks       = ["${aws_eip.gateway.public_ip}/32"]
  description       = "Nimbus Thrift from gateway node"
}

resource "aws_security_group_rule" "cloud_from_gw_workers" {
  type              = "ingress"
  security_group_id = aws_security_group.cloud_sg.id
  from_port         = 6700
  to_port           = 6703
  protocol          = "tcp"
  cidr_blocks       = ["${aws_eip.gateway.public_ip}/32"]
  description       = "Storm worker netty from gateway node"
}

resource "aws_security_group_rule" "cloud_from_gw_mysql" {
  type              = "ingress"
  security_group_id = aws_security_group.cloud_sg.id
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["${aws_eip.gateway.public_ip}/32"]
  description       = "MySQL from gateway node (Bolt_avg DB writes)"
}

# Cloud → Gateway: worker netty (tuple + ack) và MQTT (sum/forecast gửi
# notification + log về broker nhà)
resource "aws_security_group_rule" "gw_from_cloud_workers" {
  type              = "ingress"
  security_group_id = aws_security_group.gateway_sg.id
  from_port         = 6700
  to_port           = 6703
  protocol          = "tcp"
  cidr_blocks       = ["${aws_eip.cloud.public_ip}/32"]
  description       = "Storm worker netty from cloud node"
}

resource "aws_security_group_rule" "gw_from_cloud_mqtt" {
  type              = "ingress"
  security_group_id = aws_security_group.gateway_sg.id
  from_port         = 1883
  to_port           = 1883
  protocol          = "tcp"
  cidr_blocks       = ["${aws_eip.cloud.public_ip}/32"]
  description       = "MQTT notifications/logs from cloud bolts"
}
