#!/usr/bin/env bash
# DESTRUCTIVE: destroys all AWS infrastructure created by Terraform.
# All data on EBS volumes will be permanently lost.
set -euo pipefail

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  WARNING: This will PERMANENTLY DELETE all AWS resources ║"
echo "║  including EC2 instances, VPC, and Security Groups.      ║"
echo "╚══════════════════════════════════════════════════════════╝"
read -rp "Type 'yes' to confirm: " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

cd "$(dirname "$0")/../terraform"
terraform destroy -auto-approve
echo "[destroy] All infrastructure destroyed."
