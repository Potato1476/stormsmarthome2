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

echo "[5] Scripts đo (bộ remeasure nghiêm ngặt)"
for s in measure_ramp.sh agg_runs.py verify_windows.sh latency_report.sh \
         kb2_offline_recovery.sh gen_parallelism.sh gen_manifest.sh anomaly_score.py; do
  if [[ -f "tools/$s" ]]; then
    case "$s" in
      *.py) python3 -m py_compile "tools/$s" 2>/dev/null && ok "tools/$s" || no "tools/$s lỗi cú pháp" ;;
      *)    bash -n "tools/$s" 2>/dev/null && ok "tools/$s" || no "tools/$s lỗi cú pháp" ;;
    esac
  else no "thiếu tools/$s"; fi
done

echo "[6] Cloud EC2 ($CLOUD_IP) — cần để đo WAN + KB2"
if curl -s -m 6 -o /dev/null "http://$CLOUD_IP:8080/"; then ok "Storm UI :8080 phản hồi"
else wn "Storm UI :8080 KHÔNG phản hồi — stack cloud chưa up hoặc Security Group chặn IP (xem PROMPTS.md mục cuối)"; fi
if curl -s -m 6 "http://$CLOUD_IP:8000/metrics" 2>/dev/null | grep -q "topology_stats\|storm"; then ok "exporter :8000 có metric"
else wn "exporter :8000 chưa có metric (topology fog-cloud đã submit chưa?)"; fi

echo "[7] Remeasure readiness (workload parity + bộ đo dùng chung)"
PROM="${PROM:-http://localhost:9090}"
# fresh jars (đã rebuild sau khi sửa code chưa?)
for j in fog-cloud/target/fog-cloud-1.0-jar-with-dependencies.jar fog-gateway/target/fog-gateway-1.0-jar-with-dependencies.jar; do
  [[ -f "$j" ]] && ok "jar có: $(basename "$j")" || no "thiếu $j — rebuild (xem DO_DAC.md mục 0)"
done
# Prometheus + đúng metric mà measure_ramp.sh dùng
if curl -s -m 6 "$PROM/api/v1/query?query=up" >/dev/null 2>&1; then
  ok "Prometheus $PROM phản hồi"
  CAPV=$(curl -s --get "$PROM/api/v1/query" --data-urlencode 'query=max(bolts_capacity)' 2>/dev/null \
        | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'none')" 2>/dev/null)
  [[ "$CAPV" != "none" && -n "$CAPV" ]] && ok "metric bolts_capacity có (=$CAPV) — measure_ramp.sh đo được" \
    || wn "chưa thấy bolts_capacity (topology đã submit + exporter scrape chưa?)"
else wn "Prometheus $PROM không phản hồi (chỉ cần khi bắt đầu đo)"; fi
# Workload parity banner từ cloud (forecast + windows + cloudmerge mode)
if [[ -n "${KEY:-}" ]] && ssh -i "${KEY}" -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new ec2-user@"$CLOUD_IP" true 2>/dev/null; then
  BANNER=$(ssh -i "$KEY" ec2-user@"$CLOUD_IP" "docker logs cloud-topo-submit 2>&1 | grep -m1 WORKLOAD" 2>/dev/null)
  [[ -n "$BANNER" ]] && ok "parity: $BANNER" || wn "chưa thấy [WORKLOAD] banner (submit lại topology để in)"
else wn "đặt KEY=~/.ssh/storm.pem để tự kiểm tra workload banner trên cloud"; fi

echo "═══════════════════════════════════════════════"
echo " KẾT QUẢ: $pass PASS / $warn WARN / $fail FAIL"
(( fail > 0 )) && echo " ❌ Sửa các mục FAIL trước khi chạy kịch bản." || echo " ✅ Đủ điều kiện chạy (WARN về cloud có thể xử lý sau nếu chỉ chạy KB1 không cần WAN)."
echo "═══════════════════════════════════════════════"
exit 0
