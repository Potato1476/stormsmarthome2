#!/usr/bin/env bash
# Khởi động lại EC2 Cloud (tiết kiệm chi phí: stop khi không đo).
set -euo pipefail

TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
REGION=$(cd "$TF_DIR" && terraform output -raw aws_region 2>/dev/null || echo "ap-southeast-1")

CLOUD_INSTANCE_ID=$(cd "$TF_DIR" && terraform show -json | \
  python3 -c "import sys,json; r=json.load(sys.stdin)['values']['root_module']['resources']; \
  print(next(x['values']['id'] for x in r if x['name']=='cloud'))")

echo "[start] Khởi động EC2 Cloud: $CLOUD_INSTANCE_ID"
aws ec2 start-instances --instance-ids "$CLOUD_INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-running --instance-ids "$CLOUD_INSTANCE_ID" --region "$REGION"

echo "[start] Xong. IP public mới:"
aws ec2 describe-instances --instance-ids "$CLOUD_INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' --output text
echo "[start] Lưu ý: IP có thể đổi sau khi start lại → cập nhật CLOUD_PUBLIC_IP trong .env.gateway"
echo "        và sửa lại fog-monitoring/prometheus/prometheus.gateway.yml."
