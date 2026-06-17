#!/usr/bin/env bash
# ============================================================================
# ORCHESTRATOR (GIẢ LẬP) — chạy TRỌN thí nghiệm 1 môi trường, tự động A→Z,
# hoàn toàn trên laptop (gateway giả lập bằng Docker). Cloud vẫn là EC2.
# Bạn chạy 1 lệnh rồi vào lấy kết quả trong results/.
#
#   ENV=A : 8 gateway giả lập (Fog phân tán)
#   ENV=B : 1 gateway giả lập (Single Fog-Assisted, RAM nhỏ nhất)
#
# Phase (mặc định cả hai): kb1 (scalability số nhà) + kb2 (cloud off 5').
#
# Dùng:
#   ENV=A CLOUD_IP=<eip-cloud> KEY=~/.ssh/<key>.pem ./tools/run_sim_experiments.sh
#   ENV=B CLOUD_IP=<eip-cloud> KEY=~/.ssh/<key>.pem ./tools/run_sim_experiments.sh
#
# Env thêm: PHASES="kb1 kb2"  HOUSES="1 5 10 20 40"
#   STEP_DUR=300 (kb1: giây giữ mỗi nấc ramp)   OUTAGE_SEC=300 (kb2)
#   JAVA_OPTS (heap mỗi gw — thử RAM nhỏ hơn để ép bottleneck)
#
# ĐIỀU KIỆN: đã build image fog-gateway:latest; Cloud EC2 đang chạy +
# topology fog-cloud đã submit; .env.gateway có CLOUD_PUBLIC_IP
# (set-cloud-ip.sh) + prometheus.gateway.yml đã điền IP cloud.
# ============================================================================
set -euo pipefail

ENV="${ENV:?Cần ENV=A hoặc ENV=B}"
CLOUD_IP="${CLOUD_IP:?Cần CLOUD_IP=<EIP cloud EC2>}"
KEY="${KEY:?Cần KEY=~/.ssh/<key>.pem}"
PHASES="${PHASES:-kb1 kb2}"
HOUSES="${HOUSES:-1 5 10 20 40}"
STEP_DUR="${STEP_DUR:-300}"; OUTAGE_SEC="${OUTAGE_SEC:-300}"
PUBLISHER_DIR="${PUBLISHER_DIR:-$HOME/iot-data-publisher}"
COMPOSE=docker-compose.gateway.yml
cd "$(dirname "$0")/.."

case "$ENV" in
  A) PROFILE=multi;  OTHER=single; GW_SVC="gw-01 gw-02 gw-03 gw-04 gw-05 gw-06 gw-07 gw-08"; ENVNAME="A-multi8gw";;
  B) PROFILE=single; OTHER=multi;  GW_SVC="gw-single"; ENVNAME="B-single";;
  *) echo "ENV phải là A hoặc B"; exit 1;;
esac

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ THÍ NGHIỆM GIẢ LẬP — môi trường $ENVNAME | phases: $PHASES"
echo "║ Cloud=$CLOUD_IP | nhà=[$HOUSES]"
echo "╚══════════════════════════════════════════════════════════════╝"

if ! docker image inspect fog-gateway:latest >/dev/null 2>&1; then
  echo "❌ Chưa có image fog-gateway:latest. Chạy: docker build -t fog-gateway:latest ./fog-gateway"; exit 1
fi
[[ -f .env.gateway ]] || { echo "❌ Thiếu .env.gateway (chạy ./infrastructure/scripts/set-cloud-ip.sh $CLOUD_IP)"; exit 1; }

# ── Up đúng profile (tắt môi trường kia cho sạch) ────────────────────────────
echo "[setup] Tắt profile $OTHER, up profile $PROFILE + monitoring..."
docker compose -f "$COMPOSE" --profile "$OTHER" --env-file .env.gateway down 2>/dev/null || true
docker compose -f "$COMPOSE" --profile "$PROFILE" --env-file .env.gateway up -d
echo "[setup] Chờ 40s cho gateway + scrape ổn định..."
sleep 40

# ── PHASE kb1 ────────────────────────────────────────────────────────────────
if [[ " $PHASES " == *" kb1 "* ]]; then
  echo ""; echo "████ PHASE KB1 — scalability ($ENVNAME) ████"
  ENV="$ENV" CLOUD_IP="$CLOUD_IP" KEY="$KEY" HOUSES="$HOUSES" \
  STEP_DUR="$STEP_DUR" PUBLISHER_DIR="$PUBLISHER_DIR" \
  ./tools/sim_scalability.sh
fi

# ── PHASE kb2 (đủ 40 nhà) ────────────────────────────────────────────────────
if [[ " $PHASES " == *" kb2 "* ]]; then
  echo ""; echo "████ PHASE KB2 — cloud offline ${OUTAGE_SEC}s ($ENVNAME) ████"
  docker compose -f "$COMPOSE" --profile "$PROFILE" --env-file .env.gateway restart $GW_SVC >/dev/null 2>&1 || true
  sleep 20
  echo "[kb2] Bắn nền 40 nhà..."
  ( cd "$PUBLISHER_DIR" && mkdir -p logs && \
    BROKER_HOST=localhost MIN_HOUSE=0 MAX_HOUSE=39 SPEED=10 DURATION=$((OUTAGE_SEC+900)) \
    ./send_all.sh > "logs/kb2-${ENVNAME}_send.log" 2>&1 ) &
  PUB=$!; trap 'kill $PUB 2>/dev/null || true' INT TERM
  echo "[kb2] Warmup 300s trước khi cắt cloud..."
  sleep 300
  CLOUD_IP="$CLOUD_IP" KEY="$KEY" OUTAGE_SEC="$OUTAGE_SEC" ./tools/kb2_offline_recovery.sh || true
  kill $PUB 2>/dev/null || true; wait $PUB 2>/dev/null || true
  LATEST=$(ls -t results/kb2_offline_*.md 2>/dev/null | head -1 || true)
  [[ -n "$LATEST" ]] && cp "$LATEST" "results/kb2_${ENVNAME}_$(basename "$LATEST")"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ XONG môi trường $ENVNAME. Kết quả:"
echo "║   results/sim_${ENVNAME}_scalability.csv   (KB1)"
echo "║   results/kb2_${ENVNAME}_*.md             (KB2)"
echo "║   results/sim_stats_sim-${ENVNAME}-*.csv   (CPU/RAM container từng nấc)"
echo "║   results/img/sim-${ENVNAME}-*.png         (ảnh Grafana)"
echo "║ Chạy lại ENV=$([[ $ENV == A ]] && echo B || echo A) để có cặp so sánh."
echo "╚══════════════════════════════════════════════════════════════╝"
