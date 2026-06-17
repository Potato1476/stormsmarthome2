#!/usr/bin/env bash
# ============================================================================
# PREFLIGHT — kiểm tra môi trường trước khi chạy kịch bản. In PASS/WARN/FAIL.
# Dùng:  ./tools/preflight.sh   (hoặc CLOUD_IP=52.74.153.60 ./tools/preflight.sh)
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
PUB="${PUBLISHER_DIR:-$HOME/iot-data-publisher}"
CLOUD_IP="${CLOUD_IP:-52.74.153.60}"
pass=0; warn=0; fail=0
ok()   { echo "  ✅ $*"; pass=$((pass+1)); }
wn()   { echo "  ⚠️  $*"; warn=$((warn+1)); }
no()   { echo "  ❌ $*"; fail=$((fail+1)); }

echo "═══ PREFLIGHT — kiểm tra môi trường ($(date '+%H:%M:%S')) ═══"

echo "[1] Công cụ cơ bản"
for c in docker python3 curl ssh node; do
  command -v "$c" >/dev/null && ok "$c có" || no "thiếu $c"
done
docker compose version >/dev/null 2>&1 && ok "docker compose (v2) có" || no "thiếu docker compose v2"
docker info >/dev/null 2>&1 && ok "docker daemon đang chạy" || no "docker daemon CHƯA chạy (mở Docker Desktop)"

echo "[2] Image + compose"
docker image inspect fog-gateway:latest >/dev/null 2>&1 \
  && ok "image fog-gateway:latest có" \
  || no "CHƯA có image — chạy: docker build -t fog-gateway:latest ./fog-gateway"
CLOUD_PUBLIC_IP="$CLOUD_IP" docker compose -f docker-compose.gateway.yml --profile multi config >/dev/null 2>&1 \
  && ok "compose profile multi hợp lệ" || no "compose profile multi LỖI"
CLOUD_PUBLIC_IP="$CLOUD_IP" docker compose -f docker-compose.gateway.yml --profile single config >/dev/null 2>&1 \
  && ok "compose profile single hợp lệ" || no "compose profile single LỖI"

echo "[3] Cấu hình IP cloud"
if [[ -f .env.gateway ]] && grep -q "^CLOUD_PUBLIC_IP=$CLOUD_IP" .env.gateway; then
  ok ".env.gateway → CLOUD_PUBLIC_IP=$CLOUD_IP"
elif [[ -f .env.gateway ]]; then
  wn ".env.gateway có nhưng IP khác $CLOUD_IP (chạy ./infrastructure/scripts/set-cloud-ip.sh $CLOUD_IP)"
else
  no "thiếu .env.gateway (chạy ./infrastructure/scripts/set-cloud-ip.sh $CLOUD_IP)"
fi
grep -q "${CLOUD_IP}:8000" fog-monitoring/prometheus/prometheus.gateway.yml \
  && ok "prometheus scrape ${CLOUD_IP}:8000" \
  || wn "prometheus.gateway.yml chưa trỏ $CLOUD_IP (chạy set-cloud-ip.sh)"

echo "[4] Publisher ($PUB)"
[[ -d "$PUB" ]] && ok "thư mục publisher có" || no "không thấy $PUB"
[[ -x "$PUB/ramp.sh" ]] && ok "ramp.sh có (KB1)" || no "thiếu/không +x ramp.sh"
[[ -x "$PUB/send_all.sh" ]] && ok "send_all.sh có (KB2)" || no "thiếu/không +x send_all.sh"
[[ -d "$PUB/node_modules" ]] && ok "node_modules có" || no "chưa cài: cd $PUB && npm install"
NC=$(ls "$PUB"/data-file/house-*.csv 2>/dev/null | wc -l | tr -d ' ')
[[ "$NC" == "40" ]] && ok "đủ 40 file dữ liệu nhà" || wn "có $NC/40 file house-*.csv"

echo "[5] Scripts đo (stormsmarthome2)"
for s in observe_ramp.sh observe_offline.sh collect_sim_stats.sh kb2_offline_recovery.sh; do
  [[ -x "tools/$s" ]] && bash -n "tools/$s" 2>/dev/null && ok "tools/$s" || no "tools/$s lỗi/không +x"
done

echo "[6] Cloud EC2 ($CLOUD_IP) — cần để đo WAN + KB2"
if curl -s -m 6 -o /dev/null "http://$CLOUD_IP:8080/"; then ok "Storm UI :8080 phản hồi"
else wn "Storm UI :8080 KHÔNG phản hồi — stack cloud chưa up hoặc Security Group chặn IP (xem PROMPTS.md mục cuối)"; fi
if curl -s -m 6 "http://$CLOUD_IP:8000/metrics" 2>/dev/null | grep -q "topology_stats\|storm"; then ok "exporter :8000 có metric"
else wn "exporter :8000 chưa có metric (topology fog-cloud đã submit chưa?)"; fi

echo "═══════════════════════════════════════════════"
echo " KẾT QUẢ: $pass PASS / $warn WARN / $fail FAIL"
(( fail > 0 )) && echo " ❌ Sửa các mục FAIL trước khi chạy kịch bản." || echo " ✅ Đủ điều kiện chạy (WARN về cloud có thể xử lý sau nếu chỉ chạy KB1 không cần WAN)."
echo "═══════════════════════════════════════════════"
exit 0
