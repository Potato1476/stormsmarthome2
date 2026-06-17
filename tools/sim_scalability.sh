#!/usr/bin/env bash
# ============================================================================
# KỊCH BẢN 1 (giả lập) — Scalability kiểu RAMP LIÊN TỤC.
# MỘT phiên duy nhất: bắt đầu 1 nhà → vài phút sau THÊM thành 5 nhà → 10 → 20
# → 40, gateway KHÔNG restart giữa chừng. Tổng ~ (số nấc × STEP_DUR).
# Khác hẳn cách cũ (mỗi nấc 36' riêng → 3 tiếng).
#
#   ENV=A : 8 gateway giả lập (Fog phân tán)        — profile "multi"
#   ENV=B : 1 gateway giả lập (Single Fog-Assisted)  — profile "single"
#
# Mỗi nấc giữ STEP_DUR giây; ~60s cuối nấc đo CPU/RAM container + đọc metric
# (lúc tải đã ổn định) → 1 dòng CSV. Cuối phiên xuất 1 ảnh Grafana cho cả
# timeline ramp (đường bậc thang đi lên — rất trực quan cho báo cáo).
#
# Dùng trực tiếp (stack đã up đúng profile):
#   ENV=A CLOUD_IP=52.74.153.60 KEY=~/.ssh/<k>.pem ./tools/sim_scalability.sh
# Env: HOUSES="1 5 10 20 40"  STEP_DUR=300  SPEED=10
#      PUBLISHER_DIR=~/iot-data-publisher  PROM=http://localhost:9090
# ============================================================================
set -euo pipefail

ENV="${ENV:?Cần ENV=A hoặc ENV=B}"
CLOUD_IP="${CLOUD_IP:-}"; KEY="${KEY:-}"
HOUSES="${HOUSES:-1 5 10 20 40}"   # các mốc SỐ NHÀ tích lũy
STEP_DUR="${STEP_DUR:-300}"        # giây giữ mỗi nấc (>=120 để window 600 đỡ trộn)
SPEED="${SPEED:-10}"
PUBLISHER_DIR="${PUBLISHER_DIR:-$HOME/iot-data-publisher}"
PROM="${PROM:-http://localhost:9090}"
COMPOSE="${COMPOSE:-docker-compose.gateway.yml}"
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR"
cd "$(dirname "$0")/.."

case "$ENV" in
  A) PROFILE=multi;  GW_SVC="gw-01 gw-02 gw-03 gw-04 gw-05 gw-06 gw-07 gw-08"; ENVNAME="A-multi8gw";;
  B) PROFILE=single; GW_SVC="gw-single"; ENVNAME="B-single";;
  *) echo "ENV phải là A hoặc B"; exit 1;;
esac
SUMMARY="$OUT_DIR/sim_${ENVNAME}_scalability.csv"
STAT_DUR=60                        # đo CPU/RAM trong 60s cuối mỗi nấc
[[ "$STEP_DUR" -le "$STAT_DUR" ]] && STAT_DUR=$(( STEP_DUR / 2 ))

q() {
  curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c "import sys,json
try:
    r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 'NA')
except Exception: print('NA')"
}
wan_rx() {
  [[ -z "$CLOUD_IP" || -z "$KEY" ]] && { echo NA; return; }
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "ec2-user@$CLOUD_IP" \
    "docker exec cloud-mqtt cat /sys/class/net/eth0/statistics/rx_bytes" 2>/dev/null || echo NA
}

WORK="$(mktemp -d)"; PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# Mỗi nhà = 1 process node chạy trong cwd RIÊNG → .publish.stat không đụng nhau,
# nên thêm nhà mới không làm reset/ảnh hưởng các nhà đang chạy.
start_house() {
  local h="$1" d="$WORK/h$h"
  mkdir -p "$d"
  [[ -f "$PUBLISHER_DIR/data-file/house-$h.csv" ]] || { echo "  ⚠️ thiếu house-$h.csv"; return; }
  ( cd "$d" && node "$PUBLISHER_DIR/index.js" -f "$PUBLISHER_DIR/data-file/house-$h.csv" \
       -s "$SPEED" -b localhost:1883 -t iot-data >"$d/log" 2>&1 ) &
  PIDS+=("$!")
}

echo "═══ RAMP scalability | môi trường $ENVNAME | nấc nhà: $HOUSES | mỗi nấc ${STEP_DUR}s ═══"
TOTAL=$(( $(echo $HOUSES | wc -w) * STEP_DUR ))
echo "    Tổng phiên ≈ $((TOTAL/60)) phút (so với cách cũ 36'/nấc)."
[[ -z "$CLOUD_IP" || -z "$KEY" ]] && echo "⚠️ Thiếu CLOUD_IP/KEY → bỏ qua WAN."

echo "[0] Reset counter gateway 1 lần đầu phiên..."
docker compose -f "$COMPOSE" --profile "$PROFILE" restart $GW_SVC >/dev/null 2>&1 || echo "  ⚠️ restart lỗi (đã up chưa?)"
sleep 20

: > "$SUMMARY"
echo "houses,msg_per_s,complete_latency_ms,cloud_capacity_max,gw_capacity_max,gw_exec_latency_ms,gw_cpu_busiest_avg_pct,gw_ram_busiest_avg_mb,tuples_processed,wan_kb_per_min,oom_killed" >> "$SUMMARY"

T_START_MS=$(($(date +%s)*1000))
prev=0; WAN_PREV=$(wan_rx)
for N in $HOUSES; do
  echo ""; echo "──────── NẤC $N NHÀ (thêm nhà $prev..$((N-1))) ────────"
  for h in $(seq "$prev" $((N-1))); do start_house "$h"; done
  prev="$N"

  HOLD=$(( STEP_DUR - STAT_DUR )); (( HOLD < 0 )) && HOLD=0
  echo "  giữ tải ${STEP_DUR}s (ổn định ${HOLD}s + đo ${STAT_DUR}s)..."
  sleep "$HOLD"

  LABEL="sim-${ENVNAME}-h$(printf '%02d' "$N")"
  OUT_DIR="$OUT_DIR" ./tools/collect_sim_stats.sh "$LABEL" "$STAT_DUR" 10 >"$OUT_DIR/${LABEL}_simstats.log" 2>&1 || true

  CL=$(q 'avg(topology_stats_complete_latency{window="600"})'); [[ "$CL" == NA ]] && CL=$(q 'avg(topology_stats_complete_latency{window="all-time"})')
  CAPC=$(q 'max(bolts_capacity{window="600"})')
  CAPG=$(q 'max(fog_gateway_bolt_capacity)')
  LATG=$(q 'max(fog_gateway_bolt_execute_latency_ms)')
  TUP=$(q 'sum(fog_gateway_tuples_processed_total)')
  read -r CPUB RAMB <<<"$(python3 - "$OUT_DIR/sim_stats_${LABEL}.csv" <<'PY'
import csv,sys
try:
    rows=[r for r in csv.DictReader(open(sys.argv[1])) if r['gw_count'] and int(r['gw_count'])>0]
    c=[float(r['cpu_max_pct']) for r in rows]; m=[float(r['mem_max_mb']) for r in rows]
    print(f"{sum(c)/len(c):.1f} {sum(m)/len(m):.0f}")
except Exception: print("NA NA")
PY
)"
  WAN_NOW=$(wan_rx)
  if [[ "$WAN_PREV" != NA && "$WAN_NOW" != NA ]]; then
    WANKB=$(python3 -c "print(round(($WAN_NOW-$WAN_PREV)/1024/($STEP_DUR/60),1))")
  else WANKB=NA; fi
  WAN_PREV="$WAN_NOW"
  OOM=$(docker ps -a --filter 'status=exited' --format '{{.Names}} {{.Status}}' | grep -E '^gw-' | grep -ci 'oom' || true)

  echo "$N,$((N*SPEED)),$CL,$CAPC,$CAPG,$LATG,$CPUB,$RAMB,$TUP,$WANKB,$OOM" >> "$SUMMARY"
  echo "  → CL=$CL ms | cap cloud/gw=$CAPC/$CAPG | CPU gw bận nhất=$CPUB% | RAM=$RAMB MB | WAN+=$WANKB KB/ph | OOM=$OOM"
done

T_END_MS=$(($(date +%s)*1000))
echo ""; echo "═══ XONG ramp $ENVNAME — SỐ CHUẨN: $SUMMARY ═══"
column -s, -t "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo "📸 Chụp tay tại: ${GRAFANA:-http://localhost:3000}/d/fog-vs-mono-001/fog?from=$T_START_MS&to=$T_END_MS&tz=Asia%2FHo_Chi_Minh"
echo "   (panel 'Gateway: Tuple Ingestion Rate' = đường bậc thang). Lưu vào results/img/kb1-${ENVNAME}/"
