#!/usr/bin/env bash
# ============================================================================
# Cập nhật IP Cloud vào .env.gateway VÀ prometheus.gateway.yml chỉ bằng 1 lệnh.
#
# Dùng khi:
#   - Lần đầu sau terraform apply.
#   - Sau mỗi lần start lại EC2 nếu IP đổi (nếu đã bật Elastic IP thì IP không
#     đổi → chỉ cần chạy 1 lần duy nhất).
#
# Cách dùng:
#   ./infrastructure/scripts/set-cloud-ip.sh           # tự đọc terraform output
#   ./infrastructure/scripts/set-cloud-ip.sh 13.1.2.3  # truyền IP thủ công
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IP="${1:-}"

if [[ -z "$IP" ]]; then
  IP=$(cd "$REPO_ROOT/infrastructure/terraform" && terraform output -raw cloud_public_ip 2>/dev/null || true)
fi
if [[ -z "$IP" ]]; then
  echo "[set-ip] Không lấy được IP. Truyền vào trực tiếp: $0 <IP>"
  exit 1
fi
echo "[set-ip] CLOUD_PUBLIC_IP = $IP"

# ── 1) .env.gateway ──────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env.gateway"
[[ -f "$ENV_FILE" ]] || cp "$REPO_ROOT/.env.gateway.example" "$ENV_FILE"
if grep -q '^CLOUD_PUBLIC_IP=' "$ENV_FILE"; then
  sed -i.bak "s/^CLOUD_PUBLIC_IP=.*/CLOUD_PUBLIC_IP=$IP/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
else
  echo "CLOUD_PUBLIC_IP=$IP" >> "$ENV_FILE"
fi

# ── 2) prometheus.gateway.yml (target cloud-storm-exporter kết thúc bằng :8000) ─
PROM="$REPO_ROOT/fog-monitoring/prometheus/prometheus.gateway.yml"
sed -i.bak -E "s/- targets: \['[^']*:8000'\]/- targets: ['$IP:8000']/" "$PROM" && rm -f "$PROM.bak"

echo "[set-ip] Đã cập nhật:"
grep -n '^CLOUD_PUBLIC_IP=' "$ENV_FILE" | sed 's/^/  .env.gateway:        /'
grep -n ":8000'" "$PROM"               | sed 's/^/  prometheus.gateway:  /'
echo "[set-ip] Nhớ restart nếu gateway đang chạy:"
echo "  docker compose -f docker-compose.gateway.yml --env-file .env.gateway up -d"
echo "  docker compose -f docker-compose.gateway.yml restart fog-prometheus"
