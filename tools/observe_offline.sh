#!/usr/bin/env bash
# ============================================================================
# OBSERVE OFFLINE — phía stormsmarthome2 ĐO kịch bản 2 (Cloud Offline → Recovery).
# KHÔNG tự bắn data. Nó sẽ: reset gateway → bảo bạn bắn data nền 40 nhà →
# chờ data + warmup → tự tắt cloud-mqtt 5' rồi bật lại → đo Max Queue Depth /
# Recovery Time / Data Loss → xuất ảnh + in nơi lưu.
#
# Dùng:
#   ENV=A CLOUD_IP=52.74.153.60 KEY=~/.ssh/<key>.pem ./tools/observe_offline.sh
# Env: OUTAGE_SEC=300  WARMUP=180  PROM=http://localhost:9090
# ============================================================================
set -euo pipefail

ENV="${ENV:?Cần ENV=A hoặc ENV=B}"
CLOUD_IP="${CLOUD_IP:?Cần CLOUD_IP}"; KEY="${KEY:?Cần KEY}"
OUTAGE_SEC="${OUTAGE_SEC:-300}"; WARMUP="${WARMUP:-180}"
PROM="${PROM:-http://localhost:9090}"
GRAFANA="${GRAFANA:-http://localhost:3000}"
COMPOSE="${COMPOSE:-docker-compose.gateway.yml}"
ENVFILE="${ENVFILE:-.env.gateway}"
OUT_DIR="${OUT_DIR:-results}"; mkdir -p "$OUT_DIR"
cd "$(dirname "$0")/.."

case "$ENV" in
  A) PROFILE=multi;  GW_SVC="gw-01 gw-02 gw-03 gw-04 gw-05 gw-06 gw-07 gw-08"; ENVNAME="A-multi8gw";;
  B) PROFILE=single; GW_SVC="gw-single"; ENVNAME="B-single";;
  *) echo "ENV phải là A hoặc B"; exit 1;;
esac

qnum() {
  local v; v=$(curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c "import sys,json
try:
    r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 0)
except Exception: print(0)")
  echo "${v:-0}"
}

echo "[observe] Reset counter gateway ($ENVNAME)..."
docker compose -f "$COMPOSE" --env-file "$ENVFILE" --profile "$PROFILE" restart $GW_SVC >/dev/null 2>&1 || echo "  ⚠️ restart lỗi (stack đã up đúng profile chưa?)"
sleep 15
BASE=$(qnum 'sum(fog_gateway_tuples_processed_total)')

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ ▶▶▶ HÃY BẮN DATA NỀN: ở ~/iot-data-publisher chạy:"
echo "║        SPEED=10 DURATION=$((OUTAGE_SEC+1200)) ./send_all.sh"
echo "║ (40 nhà liên tục. Đừng tắt khi cloud offline — để queue dâng lên.)"
echo "╚══════════════════════════════════════════════════════════════╝"

WAITED=0
until (( $(python3 -c "print(1 if float('$(qnum 'sum(fog_gateway_tuples_processed_total)')')>float('$BASE')+1 else 0)") )); do
  sleep 5; WAITED=$((WAITED+5)); (( WAITED % 30 == 0 )) && echo "  ...đang chờ data ($WAITED s)"
  (( WAITED >= 900 )) && { echo "❌ 15' không thấy data. Đã chạy send_all.sh chưa?"; exit 1; }
done
echo "✅ Có data. Warmup ${WARMUP}s cho hệ ổn định trước khi cắt cloud..."
echo ""
echo "📺 MỞ SẴN Grafana để xem queue dâng lên rồi xả về 0 (chụp sau khi xong):"
echo "   $GRAFANA/d/fog-vs-mono-001/fog?refresh=5s&from=now-15m&to=now  (admin/admin)"
echo "   → panel 'Gateway: Store-and-Forward Queue Depth'."
sleep "$WARMUP"

echo "[observe] Chạy bài test cắt cloud ${OUTAGE_SEC}s..."
T_TEST_START_MS=$(($(date +%s)*1000))
CLOUD_IP="$CLOUD_IP" KEY="$KEY" OUTAGE_SEC="$OUTAGE_SEC" ./tools/kb2_offline_recovery.sh || true
T_END_MS=$(($(date +%s)*1000))

LATEST=$(ls -t "$OUT_DIR"/kb2_offline_*.md 2>/dev/null | head -1 || true)
TAG="$OUT_DIR/kb2_${ENVNAME}_$(basename "${LATEST:-kb2_offline_unknown.md}")"
[[ -n "$LATEST" ]] && cp "$LATEST" "$TAG"
IMGDIR="$OUT_DIR/img/kb2-${ENVNAME}"; mkdir -p "$IMGDIR"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " ✅ XONG KỊCH BẢN 2 ($ENVNAME). Bạn có thể tắt send_all.sh."
echo "════════════════════════════════════════════════════════════════"
echo " 📁 SỐ CHUẨN (Max Queue Depth / Recovery Time / Data Loss %): $TAG"
[[ -n "$LATEST" ]] && { echo "────────────────────────────────────────────────────────────────"; cat "$TAG" | sed -n '/KẾT QUẢ/,/Báo cáo này/p'; echo "────────────────────────────────────────────────────────────────"; }
echo ""
echo " 📸 GIỜ VÀO CHỤP ẢNH (minh hoạ trực quan):"
echo "    Mở:  $GRAFANA/d/fog-vs-mono-001/fog?from=$T_TEST_START_MS&to=$T_END_MS&tz=Asia%2FHo_Chi_Minh"
echo "    (login admin/admin — URL ghim đúng đoạn cắt→hồi phục)"
echo "    Chụp panel 'Gateway: Store-and-Forward Queue Depth' (đường TĂNG rồi VỀ 0)."
echo "    👉 LƯU ẢNH VÀO:  $IMGDIR/"
echo "════════════════════════════════════════════════════════════════"
