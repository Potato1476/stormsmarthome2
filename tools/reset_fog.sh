#!/usr/bin/env bash
# ============================================================================
# RESET FOG — chạy GIỮA các kịch bản để end-to-end latency không bị chồng chéo.
# Fog nhiễu NẶNG hơn mono: Bolt_cloudMerge ghi đè LẠI toàn bộ accumulator mỗi
# 60s (kể cả slice của kịch bản trước, đến 4h) → row cũ bị viết lại với updatedAt
# mới ⇒ latency giả khổng lồ. Phải xoá: DB + accumulator cloud + accumulator/queue
# gateway.
#
# Dùng:  CLOUD_IP=52.74.153.60 KEY=~/.ssh/storm.pem ./tools/reset_fog.sh
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
CLOUD_IP="${CLOUD_IP:?Cần CLOUD_IP=52.74.153.60}"
KEY="${KEY:?Cần KEY=~/.ssh/storm.pem}"
DB_USER="${DB_USER:-user1}"; DB_PASS="${DB_PASS:-Uet123}"; DB_NAME="${DB_NAME:-iotdata_fog}"
COMPOSE="${COMPOSE:-docker-compose.gateway.yml}"; ENVFILE="${ENVFILE:-.env.gateway}"

echo "[reset-fog] 1/4 Xoá store-and-forward queue, dừng bộ tối ưu + dừng gateway local..."
# Stop energy optimizer if running
if [[ -f "results/energy_optimizer.pid" ]]; then
  pid=$(cat results/energy_optimizer.pid 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "  Dừng bộ tối ưu năng lượng tự động..."
    kill "$pid" 2>/dev/null || true
  fi
  rm -f results/energy_optimizer.pid
fi

for c in $(docker ps --filter 'name=gw-' --format '{{.Names}}'); do
  docker exec "$c" sh -c 'rm -f /var/fog-queue/*/queue.jsonl' 2>/dev/null || true
done
docker compose -f "$COMPOSE" --env-file "$ENVFILE" --profile multi --profile single stop >/dev/null 2>&1 || true

echo "[reset-fog] 2/4 Dừng cloud worker (xoá accumulator Bolt_cloudMerge)..."
ssh -i "$KEY" -o StrictHostKeyChecking=no "ec2-user@$CLOUD_IP" "docker stop cloud-supervisor >/dev/null"

echo "[reset-fog] 3/4 TRUNCATE bảng fog ($DB_NAME)..."
ssh -i "$KEY" -o StrictHostKeyChecking=no "ec2-user@$CLOUD_IP" \
  "docker exec cloud-mysql mysql -u'$DB_USER' -p'$DB_PASS' '$DB_NAME' -e 'TRUNCATE fog_device_data; TRUNCATE fog_household_data; TRUNCATE fog_house_data;'"

echo "[reset-fog] 4/4 Bật lại cloud worker..."
ssh -i "$KEY" -o StrictHostKeyChecking=no "ec2-user@$CLOUD_IP" "docker start cloud-supervisor >/dev/null"
echo "[reset-fog] ✅ Xong. Bật lại gateway bằng ./demo.sh (b hoặc c) trước khi đo kịch bản kế."
