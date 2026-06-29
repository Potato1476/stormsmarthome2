#!/usr/bin/env bash
# ============================================================================
# MEASURE RAMP — bộ đo "chắc chắn", DÙNG CHUNG cho cả Fog (MODE=fog) và
# Monolithic (MODE=mono) → bảo đảm CÙNG hàm tổng hợp, CÙNG cách đo (đối xứng).
#
# Khác bản observe_ramp* cũ:
#   • Lấy MẪU CHUỖI THỜI GIAN (poll mỗi SAMPLE s) thay vì 1 snapshot cuối nấc.
#   • Tính p50/p95/max trên GIAI ĐOẠN ỔN ĐỊNH mỗi nấc (bỏ SKIP s đầu nấc).
#   • Đo WAN cả hai phía (rx_bytes của MQTT broker) — cùng điểm đo.
#   • Hỗ trợ n lần chạy (RUN_ID) → dùng agg_runs.py gộp mean±std.
#
# Dùng (Fog):
#   MODE=fog PROM=http://localhost:9090 \
#   WAN_SSH=ec2-user@52.74.153.60 WAN_KEY=~/.ssh/storm.pem WAN_CONTAINER=cloud-mqtt \
#   RUN_ID=1 OUT_DIR=results/remeasure ./tools/measure_ramp.sh
#
# Dùng (Mono): (đặt file này trong repo mono, hoặc copy sang)
#   MODE=mono PROM=http://<mono-ip>:9090 \
#   WAN_SSH=ec2-user@<mono-ip> WAN_KEY=~/Downloads/mono.pem WAN_CONTAINER=mqtt \
#   RUN_ID=1 OUT_DIR=results/remeasure ./tools/measure_ramp.sh
#
# Env: HOUSES="1 5 10 20 40" STEP_DUR=360 SKIP=90 SAMPLE=2  WAN_IFACE=eth0
#   STEP_DUR PHẢI khớp ramp.sh bên publisher.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${MODE:?Cần MODE=fog hoặc MODE=mono}"
PROM="${PROM:?Cần PROM=http://host:9090}"
HOUSES="${HOUSES:-1 5 10 20 40}"
STEP_DUR="${STEP_DUR:-360}"
SKIP="${SKIP:-90}"          # bỏ 90s đầu mỗi nấc (transient JIT/cold-start)
SAMPLE="${SAMPLE:-2}"       # poll mỗi 2s
RUN_ID="${RUN_ID:-1}"
WAN_SSH="${WAN_SSH:-}"; WAN_KEY="${WAN_KEY:-}"; WAN_CONTAINER="${WAN_CONTAINER:-}"; WAN_IFACE="${WAN_IFACE:-eth0}"
OUT_DIR="${OUT_DIR:-results/remeasure}"; mkdir -p "$OUT_DIR"

TS_FILE="$OUT_DIR/ts_${MODE}_run${RUN_ID}.tsv"
STEPS_FILE="$OUT_DIR/steps_${MODE}_run${RUN_ID}.tsv"
SUMMARY="$OUT_DIR/summary_${MODE}_run${RUN_ID}.csv"

# ── PromQL ĐỐI XỨNG: cùng biểu thức/aggregation cho cả hai hệ ────────────────
#   capacity   : max(bolts_capacity)        — bolt nghẽn nhất (gauge 0..1), SLO #1
#   latency    : max(bolts_execute_latency) — exec latency (ms) của bolt nghẽn nhất.
#                LÝ DO không dùng topology_stats_complete_latency: topology của thầy
#                phát tuple KHÔNG anchor ⇒ acker-based complete_latency & acked = 0
#                ở MỌI window (đã kiểm chứng). bolts_execute_latency là gauge, luôn
#                có giá trị, đối xứng cả mono/fog. (Độ trễ so sánh CHÉO kiến trúc =
#                e2e_first_write từ DB qua latency_report.sh — không phụ thuộc acking.)
#   throughput : sum(bolts_acked) — ĐẾM TÍCH LUỸ (exporter trả all-time cho mọi
#                window) ⇒ agg_runs tính RATE = delta/giây. Có fan-out (giải thích ở báo cáo).
CAP_EXPR='max(bolts_capacity)'
LAT_EXPR='max(bolts_execute_latency)'
ACK_EXPR='sum(bolts_acked)'
if [[ "$MODE" == fog ]]; then
  TUP_EXPR='sum(fog_gateway_tuples_processed_total)'
  GWCAP_EXPR='max(fog_gateway_bolt_capacity)'
else
  TUP_EXPR='sum(topology_stats_emitted{window=":all-time"})'
  GWCAP_EXPR='vector(0)'   # mono không có gateway
fi

q() {
  curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" 2>/dev/null \
   | python3 -c "import sys,json
try:
    r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 'nan')
except Exception: print('nan')"
}
wan_rx() {
  [[ -z "$WAN_SSH" || -z "$WAN_KEY" || -z "$WAN_CONTAINER" ]] && { echo nan; return; }
  ssh -i "$WAN_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "$WAN_SSH" \
    "docker exec $WAN_CONTAINER cat /sys/class/net/$WAN_IFACE/statistics/rx_bytes" 2>/dev/null || echo nan
}

# ── Sampler nền: ghi 1 dòng mỗi SAMPLE s ─────────────────────────────────────
echo -e "epoch\tcap\tlat\tack\ttup\tgwcap\twan_rx" > "$TS_FILE"
SAMPLER_ON=1
sampler() {
  while [[ -f "$OUT_DIR/.sampling_${MODE}_${RUN_ID}" ]]; do
    local e c l a t g w
    e=$(date +%s); c=$(q "$CAP_EXPR"); l=$(q "$LAT_EXPR"); a=$(q "$ACK_EXPR")
    t=$(q "$TUP_EXPR"); g=$(q "$GWCAP_EXPR"); w=$(wan_rx)
    echo -e "${e}\t${c}\t${l}\t${a}\t${t}\t${g}\t${w}" >> "$TS_FILE"
    sleep "$SAMPLE"
  done
}

echo "[measure:$MODE] Chờ data (tuples/emitted tăng)..."
BASE=$(q "$TUP_EXPR"); BASE=${BASE/nan/0}
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ ▶▶▶ BẮN DATA NGAY (publisher): STEP_DUR=$STEP_DUR ./ramp.sh"
echo "║ (tự bắt đầu đo khi thấy data)"
echo "╚══════════════════════════════════════════════════════════════╝"
WAITED=0
until python3 -c "import sys;sys.exit(0 if float('$(q "$TUP_EXPR" | sed s/nan/0/)')>float('$BASE')+1 else 1)"; do
  sleep 5; WAITED=$((WAITED+5)); (( WAITED>=900 )) && { echo "❌ 15' không thấy data"; exit 1; }
done
echo "✅ Có data — bắt đầu đo lúc $(date '+%H:%M:%S')"
T0_MS=$(($(date +%s)*1000)); GRAFANA="${GRAFANA:-http://localhost:3000}"

touch "$OUT_DIR/.sampling_${MODE}_${RUN_ID}"
sampler & SAMPLER_PID=$!
cleanup(){ rm -f "$OUT_DIR/.sampling_${MODE}_${RUN_ID}"; kill "$SAMPLER_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo -e "houses\tstep_start\tstep_end" > "$STEPS_FILE"
for N in $HOUSES; do
  S=$(date +%s)
  echo "──────── NẤC $N NHÀ ($STEP_DUR s) ────────"
  sleep "$STEP_DUR"
  E=$(date +%s)
  echo -e "${N}\t${S}\t${E}" >> "$STEPS_FILE"
  echo "  nấc $N: $S → $E"
done

cleanup; trap - EXIT
echo "[measure:$MODE] Đã đo xong, tổng hợp p50/p95/max (bỏ ${SKIP}s đầu mỗi nấc)..."

python3 tools/agg_runs.py step "$TS_FILE" "$STEPS_FILE" "$SKIP" "$STEP_DUR" "$MODE" > "$SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo " ✅ XONG MEASURE ($MODE, run $RUN_ID)"
column -s, -t "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo " 📁 time-series : $TS_FILE"
echo " 📁 summary 1 run: $SUMMARY"
T1_MS=$(($(date +%s)*1000))
echo " 📸 NẾU đây là RUN đại diện (vd RUN_ID=3): mở Grafana đã ghim đúng khoảng phiên rồi chụp:"
echo "    $GRAFANA/?from=$T0_MS&to=$T1_MS   (login admin/admin)"
echo "    👉 LƯU ẢNH VÀO: $OUT_DIR/img/"
echo " 👉 Chạy ≥5 lần (RUN_ID=1..5) rồi gộp: python3 tools/agg_runs.py mean $OUT_DIR $MODE"
echo "════════════════════════════════════════════════════════════════"
