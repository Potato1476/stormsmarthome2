#!/usr/bin/env bash
# ============================================================================
# KỊCH BẢN 2 — CLOUD OFFLINE → RECOVERY (kiểm chứng Store-and-Forward)
#
#   Cloud Online → tắt cloud-mqtt (OUTAGE_SEC, mặc định 300s = 5 phút)
#   → queue các gateway TĂNG → bật lại cloud-mqtt → queue XẢ VỀ 0
#
# Đo đúng 3 chỉ số được yêu cầu:
#   • Max Queue Depth  : đỉnh của sum(fog_gateway_store_queue_size)
#   • Recovery Time    : từ lúc bật lại cloud-mqtt đến lúc queue == 0
#   • Data Loss (%)    : (batch_đã_thử − batch_gửi_thành_công − còn_trong_queue)
#                        / batch_đã_thử  × 100   (kỳ vọng = 0%)
#     (flush_total đếm batch ĐÃ THỬ gửi; mqtt_published_total đếm THÀNH CÔNG,
#      kể cả khi xả queue — xem Bolt_ingest.java)
#
# Dùng (trong lúc publisher đang bắn ổn định ≥ 45 phút):
#   CLOUD_IP=<EIP fog-cloud> KEY=~/.ssh/<key>.pem ./tools/kb2_offline_recovery.sh
#
# Tham số env: OUTAGE_SEC=300  RECOVERY_TIMEOUT=900  PROM=http://localhost:9090
# Kết quả: results/kb2_offline_<timestamp>.md + ảnh Grafana panel queue depth
# ============================================================================
set -euo pipefail

CLOUD_IP="${CLOUD_IP:?Cần CLOUD_IP=<EIP fog-cloud>}"
KEY="${KEY:?Cần KEY=~/.ssh/<key>.pem}"
OUTAGE_SEC="${OUTAGE_SEC:-300}"
RECOVERY_TIMEOUT="${RECOVERY_TIMEOUT:-900}"
PROM="${PROM:-http://localhost:9090}"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "ec2-user@$CLOUD_IP")
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/kb2_offline_$(date +%Y%m%d-%H%M%S).md"
cd "$(dirname "$0")/.."

q() {
  curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c "import sys,json
try:
    r=json.load(sys.stdin)['data']['result']
    print(r[0]['value'][1] if r else 'NA')
except Exception:
    print('NA')"
}
qint() { q "$1" | python3 -c "import sys;v=sys.stdin.read().strip();print(int(float(v)) if v not in ('NA','') else 'NA')"; }

note() { echo "$*" | tee -a "$REPORT"; }

T_TEST_START_MS=$(($(date +%s)*1000))
note "# KB2 — Cloud Offline → Recovery ($(date '+%Y-%m-%d %H:%M:%S'))"
note ""
note "Outage: ${OUTAGE_SEC}s | Cloud: $CLOUD_IP"
note ""

# ── Tiền kiểm tra ────────────────────────────────────────────────────────────
Q0=$(qint 'sum(fog_gateway_store_queue_size)')
E0=$(qint 'sum(fog_gateway_queue_enqueued_total)')
D0=$(qint 'sum(fog_gateway_queue_drained_total)')
F0=$(qint 'sum(fog_gateway_flush_total)')
P0=$(qint 'sum(fog_gateway_mqtt_published_total)')
[[ "$Q0" == "NA" ]] && { echo "❌ Prometheus không trả metric gateway — stack đã chạy chưa?"; exit 1; }
note "## T0 (trước outage): queue=$Q0, enqueued=$E0, drained=$D0, flush_total=$F0, published_total=$P0"
if [[ "$Q0" != "0" ]]; then
  note "⚠️ Queue chưa về 0 trước khi test — kết quả Recovery/Loss có thể lẫn dữ liệu cũ."
fi
TUP0=$(qint 'sum(fog_gateway_tuples_processed_total)')

# ── Tắt cloud-mqtt ───────────────────────────────────────────────────────────
"${SSH[@]}" "docker stop cloud-mqtt >/dev/null"
T_OFF=$(date +%s)
note ""
note "## Cloud MQTT OFF lúc $(date '+%H:%M:%S')"

MAX_Q=0
while (( $(date +%s) - T_OFF < OUTAGE_SEC )); do
  sleep 5
  cq=$(qint 'sum(fog_gateway_store_queue_size)'); [[ "$cq" == "NA" ]] && cq=0
  (( cq > MAX_Q )) && MAX_Q=$cq
  printf '\r  queue hiện tại: %-8s max: %-8s (%ss/%ss)' "$cq" "$MAX_Q" "$(( $(date +%s) - T_OFF ))" "$OUTAGE_SEC"
done
echo ""

# ── Bật lại cloud-mqtt ───────────────────────────────────────────────────────
"${SSH[@]}" "docker start cloud-mqtt >/dev/null"
T_ON=$(date +%s)
note "## Cloud MQTT ON lại lúc $(date '+%H:%M:%S') — chờ queue xả về 0..."

RECOVERY="TIMEOUT"
while (( $(date +%s) - T_ON < RECOVERY_TIMEOUT )); do
  sleep 5
  cq=$(qint 'sum(fog_gateway_store_queue_size)'); [[ "$cq" == "NA" ]] && cq=0
  (( cq > MAX_Q )) && MAX_Q=$cq
  printf '\r  queue hiện tại: %-8s (%ss sau khi bật lại)' "$cq" "$(( $(date +%s) - T_ON ))"
  if (( cq == 0 )); then RECOVERY=$(( $(date +%s) - T_ON )); break; fi
done
echo ""

# ── Chốt số liệu (đợi thêm 1 chu kỳ flush cho counter ổn định) ───────────────
sleep 30
Q1=$(qint 'sum(fog_gateway_store_queue_size)')
E1=$(qint 'sum(fog_gateway_queue_enqueued_total)')
D1=$(qint 'sum(fog_gateway_queue_drained_total)')
F1=$(qint 'sum(fog_gateway_flush_total)')
P1=$(qint 'sum(fog_gateway_mqtt_published_total)')
TUP1=$(qint 'sum(fog_gateway_tuples_processed_total)')

ENQUEUED=$((E1 - E0))     # batch bị đẩy vào queue trong phiên test
DRAINED=$((D1 - D0))      # batch đã xả ra thành công
STUCK=$((Q1 - Q0))        # batch còn kẹt trong queue (kỳ vọng = 0)
# Mất = đã queue nhưng không drain thành công và không còn trong queue
LOSS_PCT=$(python3 -c "e=$ENQUEUED;print('NA' if e==0 else round(100.0*max(0,e-$DRAINED-$STUCK)/e,2))")
# Fallback: dùng flush_total nếu enqueued=0 (không có lần nào vào queue — kiểm tra cloud-mqtt)
if [[ "$ENQUEUED" == "0" ]]; then
  ATT=$((F1 - F0)); PUB=$((P1 - P0)); LOSTQ=$STUCK
  LOSS_PCT=$(python3 -c "a=$ATT;print('NA' if a==0 else round(100.0*(a-$PUB-$LOSTQ)/a,2))")
fi

note ""
note "## KẾT QUẢ"
note ""
note "| Chỉ số | Giá trị |"
note "|---|---|"
note "| **Max Queue Depth** | **$MAX_Q** batch |"
note "| **Recovery Time** | **${RECOVERY}s** (queue về 0 sau khi cloud online) |"
note "| **Data Loss** | **${LOSS_PCT}%** (đã queue $ENQUEUED, drain thành công $DRAINED, còn kẹt $STUCK) |"
note "| Tuples xử lý tại gateway trong phiên | $((TUP1 - TUP0)) (gateway KHÔNG dừng xử lý khi cloud offline) |"
note ""
PASS=true
(( MAX_Q > 0 )) || { PASS=false; note "❌ FAIL: queue không tăng trong outage — kiểm tra cloud-mqtt có thật sự tắt?"; }
[[ "$RECOVERY" != "TIMEOUT" ]] || { PASS=false; note "❌ FAIL: queue không xả về 0 trong ${RECOVERY_TIMEOUT}s"; }
[[ "$LOSS_PCT" == "0.0" || "$LOSS_PCT" == "0" ]] || { PASS=false; note "⚠️ Data Loss ≠ 0% — xem lại log gateway (docker logs gw-01)"; }
$PASS && note "✅ PASS: Store-and-Forward hoạt động đúng khi có lỗi mạng — queue tăng khi offline, xả hết khi online, không mất dữ liệu."

note ""
note "Báo cáo này (số chuẩn): $REPORT"
note "Ảnh minh hoạ: tự chụp panel 'Store-and-Forward Queue Depth' trên Grafana (đường tăng→về 0)."
