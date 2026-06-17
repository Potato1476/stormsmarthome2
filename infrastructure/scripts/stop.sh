#!/usr/bin/env bash
# Dừng EC2 Cloud để khỏi tốn tiền khi không chạy thực nghiệm (EBS vẫn giữ data).
set -euo pipefail

TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
REGION=$(cd "$TF_DIR" && terraform output -raw aws_region 2>/dev/null || echo "ap-southeast-1")

CLOUD_INSTANCE_ID=$(cd "$TF_DIR" && terraform show -json | \
  python3 -c "import sys,json; r=json.load(sys.stdin)['values']['root_module']['resources']; \
  print(next(x['values']['id'] for x in r if x['name']=='cloud'))")

echo "[stop] Dừng EC2 Cloud: $CLOUD_INSTANCE_ID"
aws ec2 stop-instances --instance-ids "$CLOUD_INSTANCE_ID" --region "$REGION"
aws ec2 wait instance-stopped --instance-ids "$CLOUD_INSTANCE_ID" --region "$REGION"
echo "[stop] Đã dừng. EBS volume vẫn còn dữ liệu."
