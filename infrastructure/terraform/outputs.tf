output "cloud_public_ip" {
  description = "Elastic IP TĨNH của EC2 Cloud — điền vào CLOUD_PUBLIC_IP trong .env.gateway (không đổi khi stop/start)"
  value       = aws_eip.cloud.public_ip
}

output "storm_ui_url" {
  description = "Storm UI của Cloud"
  value       = "http://${aws_eip.cloud.public_ip}:8080"
}

output "storm_exporter_url" {
  description = "Storm exporter (Prometheus local sẽ scrape target này)"
  value       = "http://${aws_eip.cloud.public_ip}:8000"
}

output "ssh_cloud" {
  description = "Lệnh SSH vào EC2 Cloud"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.cloud.public_ip}"
}

output "gateway_public_ip" {
  description = "Elastic IP TĨNH của EC2 Gateway (FOG v1) — điền vào GATEWAY_PUBLIC_IP trong cloud/.env và là BROKER_HOST của publisher"
  value       = aws_eip.gateway.public_ip
}

output "ssh_gateway" {
  description = "Lệnh SSH vào EC2 Gateway"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.gateway.public_ip}"
}

output "aws_region" {
  description = "AWS region đang dùng (cho start/stop scripts)"
  value       = var.aws_region
}
