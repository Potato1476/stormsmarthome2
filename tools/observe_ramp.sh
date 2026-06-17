#!/usr/bin/env bash
# ============================================================================
# OBSERVE RAMP — phía stormsmarthome2 ĐO kịch bản 1 (scalability ramp).
# KHÔNG tự bắn data. Bạn (hoặc Claude Code) chạy file này; nó sẽ:
#   1. Reset counter gateway, in lệnh để BẮN DATA bên iot-data-publisher.
#   2. Tự phát hiện khi data bắt đầu chảy → bắt đầu đo theo từng nấc.
#   3. Cuối phiên: ghi bảng CSV + xuất ảnh Grafana + in URL để chụp + nơi lưu.
#
# Dùng:
#   ENV=A CLOUD_IP=52.74.153.60 KEY=~/.ssh/<key>.pem ./tools/observe_ramp.sh
# Env: HOUSES="1 5 10 20 40"  STEP_DUR=300  PROM=http://localhost:9090
#   (STEP_DUR PHẢI khớp với ramp.sh bên publisher.)
# ============================================================================
set -euo pipefail

ENV="${ENV:?Cần ENV=A hoặc ENV=B}"
CLOUD_IP="${CLOUD_IP:-}"; KEY="${KEY:-}"
HOUSES="${HOUSES:-1 5 10 20 40}"
STEP_DUR="${STEP_DUR:-300}"
PROM="${PROM:-http://localhost:9090}"
COMPOSE="${COMPOSE:-docker-compose.gateway.yml}"
GRAFANA="${GRAFANA:-http://localhost:3000}"
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR/img"
cd "$(dirname "$0")/.."

case "$ENV" in
  A) PROFILE=multi;  GW_SVC="gw-01 gw-02 gw-03 gw-04 gw-05 gw-06 gw-07 gw-08"; ENVNAME="A-multi8gw";;
  B) PROFILE=single; GW_SVC="gw-single"; ENVNAME="B-single";;
  *) echo "ENV phải là A hoặc B"; exit 1;;
esac
SUMMARY="$OUT_DIR/sim_${ENVNAME}_scalability.csv"
STAT_DUR=60; [[ "$STEP_DUR" -le "$STAT_DUR" ]] && STAT_DUR=$(( STEP_DUR / 2 ))

q() {
  curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c "import sys,json
try:
    r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 'NA')
except Exception: print('NA')"
}
qnum() { local v; v=$(q "$1"); [[ "$v" == NA ]] && echo 0 || echo "$v"; }
wan_rx() {
  [[ -z "$CLOUD_IP" || -z "$KEY" ]] && { echo NA; return; }
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "ec2-user@$CLOUD_IP" \
    "docker exec cloud-mqtt cat /sys/class/net/eth0/statistics/rx_bytes" 2>/dev/null || echo NA
}

echo "[observe] Reset counter gateway ($ENVNAME)..."
ENVFILE="${ENVFILE:-.env.gateway}"
docker compose -f "$COMPOSE" --env-file "$ENVFILE" --profile "$PROFILE" restart $GW_SVC >/dev/null 2>&1 || echo "  ⚠️ restart lỗi (stack đã up đúng profile chưa?)"
sleep 15
BASE=$(qnum 'sum(fog_gateway_tuples_processed_total)')

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ ▶▶▶ HÃY BẮN DATA NGAY: mở terminal ở ~/iot-data-publisher chạy:"
echo "║        STEP_DUR=$STEP_DUR ./ramp.sh"
echo "║ (Đang chờ data chảy vào... tôi sẽ tự bắt đầu đo khi thấy data.)"
echo "╚══════════════════════════════════════════════════════════════╝"

# Chờ tuples tăng so với baseline (tối đa 15 phút)
WAITED=0
until (( $(python3 -c "print(1 if float('$(qnum 'sum(fog_gateway_tuples_processed_total)')')>float('$BASE')+1 else 0)") )); do
  sleep 5; WAITED=$((WAITED+5))
  (( WAITED % 30 == 0 )) && echo "  ...đang chờ data ($((WAITED))s)"
  (( WAITED >= 900 )) && { echo "❌ 15 phút không thấy data. Bạn đã chạy ramp.sh chưa?"; exit 1; }
done
echo "✅ Phát hiện data — bắt đầu đo lúc $(date '+%H:%M:%S')."
T_START_MS=$(($(date +%s)*1000))
echo ""
echo "📺 MỞ SẴN Grafana để theo dõi đường vẽ dần (chụp sau khi xong):"
echo "   $GRAFANA/d/fog-vs-mono-001/fog?refresh=10s&from=now-40m&to=now  (admin/admin)"
echo "   Panel đẹp cho KB1: 'Gateway: Tuple Ingestion Rate' (đường bậc thang),"
echo "   'All Gateways: Bolt Capacity', 'Cloud Bolt: Capacity'."

# Hàm đọc cloud complete_latency với fallback và retry nếu trả về 0
# Nguyên nhân: metric window chưa tích lũy đủ data → Storm báo 0 thay vì NA
read_cloud_latency() {
  local CL
  # Thử window 600s trước
  CL=$(q 'avg(topology_stats_complete_latency{window="600"})') || CL=NA
  # 0 đúng nghĩa là "chưa có tuple hoàn thành trong cửa sổ" — không phải latency thực
  if [[ "$CL" == NA || "$CL" == "0" || "$CL" == "0.0" ]]; then
    CL=$(q 'avg(topology_stats_complete_latency{window="all-time"})') || CL=NA
  fi
  # Nếu vẫn 0: đợi 20s rồi thử lại một lần
  if [[ "$CL" == "0" || "$CL" == "0.0" ]]; then
    sleep 20
    CL=$(q 'avg(topology_stats_complete_latency{window="600"})') || CL=NA
    [[ "$CL" == NA || "$CL" == "0" || "$CL" == "0.0" ]] && \
      CL=$(q 'avg(topology_stats_complete_latency{window="all-time"})') || true
  fi
  # Vẫn 0 sau retry → đánh dấu ERR (không dùng 0 vì latency thực không bao giờ = 0)
  [[ "$CL" == "0" || "$CL" == "0.0" ]] && CL=ERR
  echo "$CL"
}

: > "$SUMMARY"
echo "houses,msg_per_s,cloud_complete_latency_ms,cloud_capacity_max,gw_capacity_max,gw_exec_latency_ms,gw_flush_latency_ms,gw_cpu_busiest_avg_pct,gw_ram_busiest_avg_mb,tuples_processed,wan_kb_per_min,oom_killed" >> "$SUMMARY"

prev=0; WAN_PREV=$(wan_rx)
for N in $HOUSES; do
  echo ""; echo "──────── ĐANG ĐO NẤC $N NHÀ ────────"
  HOLD=$(( STEP_DUR - STAT_DUR )); (( HOLD < 0 )) && HOLD=0
  sleep "$HOLD"
  LABEL="sim-${ENVNAME}-h$(printf '%02d' "$N")"
  OUT_DIR="$OUT_DIR" ./tools/collect_sim_stats.sh "$LABEL" "$STAT_DUR" 10 >"$OUT_DIR/${LABEL}_simstats.log" 2>&1 || true

  CL=$(read_cloud_latency)
  CAPC=$(q 'max(bolts_capacity)')
  CAPG=$(q 'max(fog_gateway_bolt_capacity)')
  LATG=$(q 'max(fog_gateway_bolt_execute_latency_ms)')
  FLUSHLATMS=$(q 'avg(fog_gateway_flush_latency_ms)')
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
  if [[ "$WAN_PREV" != NA && "$WAN_NOW" != NA ]]; then WANKB=$(python3 -c "print(round(($WAN_NOW-$WAN_PREV)/1024/($STEP_DUR/60),1))"); else WANKB=NA; fi
  WAN_PREV="$WAN_NOW"
  OOM=$(docker ps -a --filter 'status=exited' --format '{{.Names}} {{.Status}}' | grep -E '^gw-' | grep -ci 'oom' || true)
  echo "$N,$((N*10)),$CL,$CAPC,$CAPG,$LATG,$FLUSHLATMS,$CPUB,$RAMB,$TUP,$WANKB,$OOM" >> "$SUMMARY"
  echo "  → cloud_CL=$CL ms | gw_flush=$FLUSHLATMS ms | cap cloud/gw=$CAPC/$CAPG | CPU gw=$CPUB% | RAM=$RAMB MB | WAN+=$WANKB KB/ph | OOM=$OOM"
  prev="$N"
done

T_END_MS=$(($(date +%s)*1000))
IMGDIR="$OUT_DIR/img/kb1-${ENVNAME}"; mkdir -p "$IMGDIR"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " ✅ XONG KỊCH BẢN 1 ($ENVNAME) — SỐ LIỆU THỰC (số chuẩn cho báo cáo):"
echo "════════════════════════════════════════════════════════════════"
column -s, -t "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo "────────────────────────────────────────────────────────────────"
echo " 📁 SỐ CHUẨN (dùng cho báo cáo): $SUMMARY"
echo "    + CPU/RAM từng nấc: $OUT_DIR/sim_stats_sim-${ENVNAME}-h*.csv"
echo ""
echo " 📸 GIỜ VÀO CHỤP ẢNH (ảnh chỉ để minh hoạ trực quan):"
echo "    Mở:  $GRAFANA/d/fog-vs-mono-001/fog?from=$T_START_MS&to=$T_END_MS&tz=Asia%2FHo_Chi_Minh"
echo "    (login admin/admin — URL đã ghim đúng khoảng thời gian của phiên này)"
echo "    Chụp 3 panel: 'Gateway: Tuple Ingestion Rate' (bậc thang),"
echo "                  'All Gateways: Bolt Capacity', 'Cloud Bolt: Capacity'."
echo "    👉 LƯU ẢNH VÀO:  $IMGDIR/"
echo "════════════════════════════════════════════════════════════════"
