variable "aws_region" {
  description = "AWS region — ap-southeast-1 (Singapore) is closest to Vietnam"
  type        = string
  default     = "ap-southeast-1"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "your_ip_cidr" {
  description = "Your public IP in CIDR notation — Grafana and SSH are restricted to this (e.g. 1.2.3.4/32)"
  type        = string
}

variable "cloud_instance_type" {
  description = "EC2 instance type for Cloud tier (Storm cluster + MQTT + MySQL). t3 = x86_64."
  type        = string
  default     = "t3.large"
}

variable "cloud_ami" {
  description = "x86_64 AMI for ap-southeast-1. Default: Amazon Linux 2023 x86_64."
  type        = string
  default     = "ami-0d105bf3c7d10a264"
}

variable "gateway_instance_type" {
  description = "EC2 instance type for the Gateway tier node (FOG v1). t3.small for stability; supervisor1 inside is capped to 1GB/1vCPU by docker to simulate a Pi 3."
  type        = string
  default     = "t3.small"
}

variable "db_password" {
  description = "MySQL root password for cloud-mysql — injected at runtime, never stored in state as plaintext"
  type        = string
  sensitive   = true
  default     = "Uet123"
}

variable "mqtt_topic" {
  description = "MQTT topic on which raw IoT data is published"
  type        = string
  default     = "iot-data"
}

variable "gateway_windows" {
  description = "Comma-separated window sizes in minutes processed on each gateway"
  type        = string
  default     = "1,5,10,15,30"
}

variable "flush_interval_sec" {
  description = "How often (seconds) each gateway flushes aggregated data to Cloud MQTT"
  type        = number
  default     = 60
}
