#!/usr/bin/env bash
# ============================================================================
# Publisher dữ liệu thô  →  LOCAL MQTT broker (container local-mqtt)
#
# Mô phỏng đúng luồng thực tế: dữ liệu CSV (định dạng REFIT) được bơm vào
# broker MQTT cục bộ; 8 gateway đọc, tổng hợp, rồi đẩy kết quả lên Cloud.
# Raw data KHÔNG bao giờ rời máy local.
#
# Định dạng mỗi dòng (Spout_rawData yêu cầu >= 7 trường, phân tách bằng dấu phẩy):
#     _,timestamp,value,property,plugId,householdId,houseId
#   - property = 1  → bản ghi công suất (load) — gateway chỉ xử lý property==1
#   - houseId  = 1..40 → để khớp shard của 8 gateway (mỗi gw 5 nhà)
#
# Không cần cài gì thêm: script dùng mosquitto_pub có sẵn TRONG container
# local-mqtt qua `docker exec`, đọc từng dòng (-l) làm 1 message.
#
# Dùng:
#   ./tools/publish_csv.sh duong-dan-file.csv          # bơm từ file CSV thật
#   ./tools/publish_csv.sh --synthetic 2000 200        # sinh 2000 dòng, 200 dòng/giây
#   ./tools/publish_csv.sh --synthetic                 # mặc định 2000 dòng, 200/giây
# ============================================================================
set -euo pipefail

BROKER_CONTAINER="${BROKER_CONTAINER:-local-mqtt}"
TOPIC="${TOPIC:-iot-data}"

usage() {
  echo "Usage:"
  echo "  $0 <file.csv> [rate]               # bơm từ file CSV; rate = dòng/giây (0 hoặc bỏ trống = nhanh nhất)"
  echo "  $0 --synthetic [num_rows] [rate]   # sinh dữ liệu giả lập (mặc định 2000 dòng, 200/giây)"
  echo ""
  echo "Ví dụ đo 30 phút ở 400 msg/s:  $0 workload_40nha.csv 400"
  exit 1
}
[[ $# -lt 1 ]] && usage

if ! docker ps --format '{{.Names}}' | grep -q "^${BROKER_CONTAINER}$"; then
  echo "[publish] LỖI: container '${BROKER_CONTAINER}' chưa chạy."
  echo "          Chạy gateway trước: docker compose -f docker-compose.gateway.yml --env-file .env.gateway up -d"
  exit 1
fi

if [[ "$1" == "--synthetic" ]]; then
  N="${2:-2000}"; RATE="${3:-200}"
  BASE_TS="$(( $(date +%s) * 1000 ))"   # tính ở shell cho di động (awk BSD không có systime)
  echo "[publish] Sinh $N dòng giả lập (REFIT format), ~$RATE dòng/giây → topic '$TOPIC'"
  awk -v n="$N" -v rate="$RATE" -v base="$BASE_TS" 'BEGIN{
    srand();
    for (i = 0; i < n; i++) {
      house = int(rand()*40) + 1;          # houseId 1..40
      plug  = int(rand()*5) + 1;
      val   = sprintf("%.1f", rand()*3000); # công suất W
      ts    = base + i*1000;
      printf "%d,%d,%s,1,%d,%d,%d\n", i, ts, val, plug, house, house;
      if (rate > 0 && (i+1) % rate == 0) system("sleep 1");
    }
  }' | docker exec -i "$BROKER_CONTAINER" mosquitto_pub -h localhost -t "$TOPIC" -q 1 -l
  echo "[publish] Xong."
else
  FILE="$1"; RATE="${2:-0}"   # 0 = phát nhanh nhất; >0 = khống chế dòng/giây
  [[ -f "$FILE" ]] || { echo "[publish] Không thấy file: $FILE"; exit 1; }
  N=$(wc -l < "$FILE" | tr -d ' ')
  if [[ "$RATE" -gt 0 ]]; then
    echo "[publish] Đẩy $N dòng từ '$FILE' ở ~$RATE dòng/giây (~$((N/RATE))s) → topic '$TOPIC'"
    awk -v rate="$RATE" '{ print; if (NR % rate == 0) system("sleep 1") }' "$FILE" \
      | docker exec -i "$BROKER_CONTAINER" mosquitto_pub -h localhost -t "$TOPIC" -q 1 -l
  else
    echo "[publish] Đẩy $N dòng từ '$FILE' (nhanh nhất) → topic '$TOPIC'"
    docker exec -i "$BROKER_CONTAINER" mosquitto_pub -h localhost -t "$TOPIC" -q 1 -l < "$FILE"
  fi
  echo "[publish] Xong."
fi
