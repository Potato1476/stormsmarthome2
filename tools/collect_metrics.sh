#!/usr/bin/env bash
# ============================================================================
# Thu thập 5 metric lõi (+ phụ) từ Prometheus → 1 file CSV, để SO SÁNH 2 kiến trúc.
#
# Tên metric & nhãn window lấy ĐÚNG theo exporter mr4x2/stormexporter (giống
# hệ Monolithic trong báo cáo): topology_stats_{acked,emitted,transferred},
# bolts_process_latency, bolts_capacity; window ∈ {600, 10800, 86400, all-time}.
#
# Dùng:
#   ./tools/collect_metrics.sh fog                 # đo hệ Fog (Prometheus local :9090)
#   PROM_URL=http://<IP>:9090 ./tools/collect_metrics.sh monolithic
#
# Chạy ở thời điểm T+30 phút (cuối cửa sổ quan sát), cho CẢ hai hệ giống nhau.
# ============================================================================
set -euo pipefail

PROM="${PROM_URL:-http://localhost:9090}"
LABEL="${1:-run}"          # vd: monolithic | fog
OUT_DIR="${OUT_DIR:-results}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/${LABEL}_$(date +%Y%m%d-%H%M%S).csv"

q() { # $1 = PromQL; in ra giá trị scalar đầu tiên (hoặc NA)
  curl -s --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c "import sys,json
try:
    r=json.load(sys.stdin)['data']['result']
    print(r[0]['value'][1] if r else 'NA')
except Exception:
    print('ERR')"
}

echo "metric,window,value" > "$OUT"
# ── 3 metric throughput (so sánh chính, độc lập phần cứng) ────────────────────
for w in ":all-time" 600; do
  label="${w#:}"   # strip leading colon for CSV readability
  echo "acked,$label,$(q "sum(topology_stats_acked{window=\"$w\"})")"             >> "$OUT"
  echo "emitted,$label,$(q "sum(topology_stats_emitted{window=\"$w\"})")"         >> "$OUT"
  echo "transferred,$label,$(q "sum(topology_stats_trasferred{window=\"$w\"})")" >> "$OUT"
done
# ── metric tải/độ trễ (phụ thuộc phần cứng → dùng cùng loại EC2) ──────────────
echo "max_process_latency_ms,-,$(q "max(bolts_process_latency)")"  >> "$OUT"
echo "max_bolt_capacity,-,$(q "max(bolts_capacity)")"             >> "$OUT"
echo "max_execute_latency_ms,-,$(q "max(bolts_execute_latency)")" >> "$OUT"
# ── CHỈ SỐ HEADLINE: Complete Latency end-to-end (báo cáo: 17.5ms vs 400-550ms) ─
echo "max_complete_latency_ms,600,$(q "max(topology_stats_complete_latency{window=\"600\"})")"           >> "$OUT"
echo "max_complete_latency_ms,all-time,$(q "max(topology_stats_complete_latency{window=\":all-time\"})")" >> "$OUT"
# ── Metric tầng Gateway (chỉ có ở Fog — cho thấy công việc dời về đâu) ─────────
echo "gw_tuples_processed_total,-,$(q "sum(fog_gateway_tuples_processed_total)")" >> "$OUT"
echo "gw_mqtt_published_total,-,$(q "sum(fog_gateway_mqtt_published_total)")"     >> "$OUT"
echo "gw_store_queue_size,-,$(q "sum(fog_gateway_store_queue_size)")"             >> "$OUT"

echo "── Kết quả (${LABEL}) ──"
column -s, -t "$OUT"
echo "[collect] Đã lưu: $OUT"
